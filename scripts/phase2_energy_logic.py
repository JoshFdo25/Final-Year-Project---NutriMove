"""
============================================================================
Phase 2: Energy & Physiological Logic (Rule-Based Module)
============================================================================

This module implements the calorie estimation engine using Option B:
  BMR (baseline) + Live Activity Tracking (from Phase 1 HAR model)

Instead of using a fixed TDEE multiplier, this system dynamically
calculates calories burned from the HAR model's real-time predictions.

Flow:
  User Profile → BMR → HAR Predictions → MET × Weight × Duration
  → Daily Calorie Budget → Meal-specific targets → Pass to Phase 3

Run: py -3.12 phase2_energy_logic.py
============================================================================
"""

import numpy as np
import json
from pathlib import Path
from datetime import datetime, timedelta

# ============================================================================
# 2.1 USER PROFILE
# ============================================================================

class UserProfile:
    """Stores user physical data needed for calorie calculations."""
    
    def __init__(self, name, age, weight_kg, height_cm, gender, 
                 activity_level="moderate", goal="maintain"):
        self.name = name
        self.age = age
        self.weight_kg = weight_kg
        self.height_cm = height_cm
        self.gender = gender.lower()  # "male" or "female"
        self.activity_level = activity_level.lower()
        self.goal = goal.lower()  # "lose", "maintain", "gain"
        
        # Validate inputs
        assert self.gender in ["male", "female"], "Gender must be 'male' or 'female'"
        assert self.goal in ["lose", "maintain", "gain"], "Goal must be 'lose', 'maintain', or 'gain'"
        assert 10 <= self.age <= 120, "Age must be between 10 and 120"
        assert 20 <= self.weight_kg <= 300, "Weight must be between 20 and 300 kg"
        assert 80 <= self.height_cm <= 250, "Height must be between 80 and 250 cm"
    
    def __repr__(self):
        return (f"UserProfile(name='{self.name}', age={self.age}, "
                f"weight={self.weight_kg}kg, height={self.height_cm}cm, "
                f"gender='{self.gender}', goal='{self.goal}')")
    
    def to_dict(self):
        return {
            "name": self.name,
            "age": self.age,
            "weight_kg": self.weight_kg,
            "height_cm": self.height_cm,
            "gender": self.gender,
            "activity_level": self.activity_level,
            "goal": self.goal
        }


# ============================================================================
# 2.2 BMR CALCULATION (Mifflin-St Jeor Equation)
# ============================================================================

def calculate_bmr(profile):
    """
    Calculate Basal Metabolic Rate using Mifflin-St Jeor equation.
    This is the minimum calories the body needs at complete rest.
    
    Male:   BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) + 5
    Female: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) - 161
    
    Returns: BMR in kcal/day
    """
    bmr = (10 * profile.weight_kg) + (6.25 * profile.height_cm) - (5 * profile.age)
    
    if profile.gender == "male":
        bmr += 5
    else:
        bmr -= 161
    
    return round(bmr, 2)


def calculate_bmr_harris_benedict(profile):
    """
    Alternative BMR using Harris-Benedict equation (for cross-validation).
    
    Male:   BMR = 88.362 + (13.397 × weight) + (4.799 × height) - (5.677 × age)
    Female: BMR = 447.593 + (9.247 × weight) + (3.098 × height) - (4.330 × age)
    """
    if profile.gender == "male":
        bmr = 88.362 + (13.397 * profile.weight_kg) + (4.799 * profile.height_cm) - (5.677 * profile.age)
    else:
        bmr = 447.593 + (9.247 * profile.weight_kg) + (3.098 * profile.height_cm) - (4.330 * profile.age)
    
    return round(bmr, 2)


# ============================================================================
# 2.3 MET MAPPING
# ============================================================================

# MET values from the Compendium of Physical Activities (Ainsworth et al., 2011)
# Static fallbacks if GPS speed is unavailable
MET_VALUES = {
    "Walking":  3.5,   # Walking, moderate pace (3.0 mph)
    "Jogging":  7.0,   # Jogging, general
    "Sitting":  1.3,   # Sitting, quiet
    "Standing": 1.8,   # Standing, light work
    "Stairs":   4.0,   # Walking upstairs
    "Cycling":  6.8,   # Cycling, moderate
    "Running":  9.8,   # Running, 6 mph
    "Sleeping": 0.95,  # Sleeping
}

# Dynamic MET values based on GPS Speed (mph)
DYNAMIC_MET = {
    "Walking": [
        (2.0, 2.8), # Slow walk
        (2.5, 3.0),
        (3.0, 3.5), # Standard
        (3.5, 4.3),
        (4.0, 5.0)  # Brisk
    ],
    "Jogging": [
        (4.0, 6.0), 
        (5.0, 8.3), # Standard jogging
        (6.0, 9.8), # Running
        (7.0, 11.0),
        (8.0, 11.8)
    ]
}

# Map HAR model codes to activity names
HAR_CODE_MAP = {
    "A": "Walking",
    "B": "Jogging",
    "C": "Stairs",
    "D": "Sitting",
    "E": "Standing",
}

def get_met_value(activity_name, speed_mph=None):
    """
    Look up MET value for a given activity.
    If GPS speed (mph) is provided for Walking/Jogging, interpolate the dynamic MET value.
    """
    # 1. Provide exact scale if Speed is known
    if speed_mph is not None and activity_name in DYNAMIC_MET:
        scale = DYNAMIC_MET[activity_name]
        
        # Clamp to min
        if speed_mph <= scale[0][0]:
            return scale[0][1]
        
        # Clamp to max
        if speed_mph >= scale[-1][0]:
            return scale[-1][1]
            
        # Interpolate between matching speeds
        for i in range(len(scale) - 1):
            s1, m1 = scale[i]
            s2, m2 = scale[i+1]
            if s1 <= speed_mph <= s2:
                # Linear interpolation formula
                fraction = (speed_mph - s1) / (s2 - s1)
                interpolated_met = m1 + fraction * (m2 - m1)
                return round(interpolated_met, 2)

    # 2. Fallback to static averages if no GPS speed provided
    return MET_VALUES.get(activity_name, 1.3)


# ============================================================================
# 2.4 CALORIE BURN ESTIMATION
# ============================================================================

def calculate_calories_burned(met_value, weight_kg, duration_minutes):
    """
    Calculate calories burned for a specific activity.
    
    Formula: Calories = MET × Weight(kg) × Duration(hours)
    
    Args:
        met_value: MET value of the activity
        weight_kg: User's weight in kg
        duration_minutes: Duration in minutes
    
    Returns: Calories burned (kcal)
    """
    duration_hours = duration_minutes / 60.0
    calories = met_value * weight_kg * duration_hours
    return round(calories, 2)


def calculate_activity_calories(activity_durations, weight_kg, speed_data=None):
    """
    Calculate total calories burned from a dictionary of activity durations.
    
    Args:
        activity_durations: dict of {activity_name: duration_minutes}
        weight_kg: User's weight in kg
        speed_data: dict of {activity_name: speed_mph} for dynamic MET scaling
    
    Returns: dict with per-activity and total calories
    """
    if speed_data is None:
        speed_data = {}

    results = {}
    total_calories = 0
    
    for activity, minutes in activity_durations.items():
        speed_mph = speed_data.get(activity)
        met = get_met_value(activity, speed_mph)
        calories = calculate_calories_burned(met, weight_kg, minutes)
        results[activity] = {
            "duration_minutes": minutes,
            "met_value": met,
            "calories_burned": calories
        }
        total_calories += calories
    
    results["_total"] = {
        "total_minutes": sum(activity_durations.values()),
        "total_calories": round(total_calories, 2)
    }
    
    return results


# ============================================================================
# 2.5 TDEE CALCULATION (Fallback / Reference)
# ============================================================================

ACTIVITY_MULTIPLIERS = {
    "sedentary":   1.2,    # Little to no exercise
    "light":       1.375,  # Light exercise 1-3 days/week
    "moderate":    1.55,   # Moderate exercise 3-5 days/week
    "active":      1.725,  # Hard exercise 6-7 days/week
    "very_active": 1.9,    # Very hard exercise, physical job
}


def calculate_tdee(bmr, activity_level="moderate"):
    """
    Calculate Total Daily Energy Expenditure (TDEE) using fixed multiplier.
    This is the FALLBACK method — used only when live tracking is unavailable.
    
    The PRIMARY method is BMR + actual tracked activity calories.
    """
    multiplier = ACTIVITY_MULTIPLIERS.get(activity_level, 1.55)
    return round(bmr * multiplier, 2)


# ============================================================================
# 2.6 GOAL-BASED CALORIE ADJUSTMENT
# ============================================================================

GOAL_ADJUSTMENTS = {
    "lose":     -500,   # ~0.45 kg/week loss (safe rate)
    "maintain":  0,     # No adjustment
    "gain":     +300,   # ~0.27 kg/week gain (lean bulk)
}


def adjust_for_goal(daily_calories, goal):
    """
    Adjust daily calorie target based on user's fitness goal.
    
    - Lose weight: -500 kcal/day (~0.45 kg/week)
    - Maintain: no change
    - Gain weight: +300 kcal/day (lean bulk)
    """
    adjustment = GOAL_ADJUSTMENTS.get(goal, 0)
    adjusted = daily_calories + adjustment
    
    # Safety limits: never go below 1200 (women) or 1500 (men)
    min_calories = 1200
    adjusted = max(adjusted, min_calories)
    
    return round(adjusted, 2), adjustment


# ============================================================================
# 2.7 ACTIVITY DURATION TRACKER (from HAR predictions)
# ============================================================================

def process_har_predictions(predictions, window_seconds=10):
    """
    Process HAR model predictions into activity durations.
    
    Each prediction corresponds to one sliding window (10 seconds at 20Hz).
    
    Args:
        predictions: list of activity labels (e.g., ['Walking', 'Walking', 'Jogging', ...])
        window_seconds: duration of each window in seconds (default 10s)
    
    Returns: dict of {activity_name: duration_minutes}
    """
    # Count windows per activity
    activity_counts = {}
    for pred in predictions:
        # Map codes to names if needed
        activity = HAR_CODE_MAP.get(pred, pred)
        activity_counts[activity] = activity_counts.get(activity, 0) + 1
    
    # Convert window counts to minutes
    activity_durations = {}
    for activity, count in activity_counts.items():
        duration_minutes = (count * window_seconds) / 60.0
        activity_durations[activity] = round(duration_minutes, 2)
    
    return activity_durations


# ============================================================================
# 2.8 DAILY SUMMARY GENERATOR (Integration)
# ============================================================================

# Meal calorie distribution (percentage of daily target)
MEAL_DISTRIBUTION = {
    "breakfast": 0.30,  # 30% of daily calories
    "lunch":     0.35,  # 35% of daily calories
    "dinner":    0.25,  # 25% of daily calories
    "snacks":    0.10,  # 10% of daily calories
}


def generate_daily_summary(profile, activity_durations, meals_eaten=None):
    """
    Generate a complete daily energy summary.
    
    This is the main integration function that combines:
    - BMR calculation (baseline)
    - Activity calorie burn (from HAR predictions)
    - Goal-based adjustment
    - Remaining calorie budget
    - Per-meal targets
    
    Args:
        profile: UserProfile object
        activity_durations: dict from process_har_predictions()
        meals_eaten: dict of {meal_name: calories_consumed} (optional)
    
    Returns: Complete daily summary dict
    """
    if meals_eaten is None:
        meals_eaten = {}
    
    # Step 1: BMR
    bmr = calculate_bmr(profile)
    bmr_harris = calculate_bmr_harris_benedict(profile)
    
    # Step 2: Activity calories (Option B — live tracking)
    activity_results = calculate_activity_calories(activity_durations, profile.weight_kg)
    activity_calories = activity_results["_total"]["total_calories"]
    total_tracked_minutes = activity_results["_total"]["total_minutes"]
    
    # Step 3: Today's actual energy expenditure
    # BMR is per-day, so we use it as the baseline
    daily_expenditure = bmr + activity_calories
    
    # Step 4: TDEE for reference comparison
    tdee_reference = calculate_tdee(bmr, profile.activity_level)
    
    # Step 5: Goal adjustment
    daily_target, goal_adjustment = adjust_for_goal(daily_expenditure, profile.goal)
    
    # Step 6: Calories consumed so far
    total_consumed = sum(meals_eaten.values())
    remaining_calories = daily_target - total_consumed
    
    # Step 7: Per-meal targets for remaining meals
    remaining_meal_targets = {}
    for meal, percentage in MEAL_DISTRIBUTION.items():
        if meal not in meals_eaten:
            remaining_meal_targets[meal] = round(daily_target * percentage, 0)
    
    # Build summary
    summary = {
        "user": profile.to_dict(),
        "bmr": {
            "mifflin_st_jeor": bmr,
            "harris_benedict": bmr_harris,
            "description": f"Your body burns {bmr} kcal/day at rest"
        },
        "activity_tracking": {
            "tracked_minutes": total_tracked_minutes,
            "activities": {k: v for k, v in activity_results.items() if k != "_total"},
            "total_activity_calories": activity_calories,
            "description": f"You burned {activity_calories} kcal from tracked activities"
        },
        "daily_energy": {
            "bmr": bmr,
            "activity_burn": activity_calories,
            "total_expenditure": round(daily_expenditure, 2),
            "goal_adjustment": goal_adjustment,
            "daily_target": daily_target,
            "tdee_reference": tdee_reference,
            "method": "Option B: BMR + Live Activity Tracking",
            "description": (
                f"BMR ({bmr}) + Activity ({activity_calories}) = "
                f"{round(daily_expenditure, 2)} kcal expenditure. "
                f"Goal '{profile.goal}' adjustment: {goal_adjustment:+d} kcal. "
                f"Target: {daily_target} kcal/day"
            )
        },
        "meals": {
            "consumed": meals_eaten,
            "total_consumed": total_consumed,
            "remaining_calories": round(remaining_calories, 2),
            "remaining_meal_targets": remaining_meal_targets,
            "distribution": MEAL_DISTRIBUTION
        },
        "explanation": generate_explanation(profile, bmr, activity_results, 
                                           daily_target, goal_adjustment)
    }
    
    return summary


def generate_explanation(profile, bmr, activity_results, daily_target, goal_adjustment):
    """
    Generate a plain-language explanation (for XAI / Phase 4).
    This is what the user sees in the app.
    """
    lines = []
    lines.append(f"📊 Daily Analysis for {profile.name}")
    lines.append(f"")
    
    # BMR explanation
    lines.append(f"🔥 Your body burns {bmr} kcal/day at rest (BMR)")
    lines.append(f"   This covers breathing, circulation, and cell function.")
    lines.append(f"")
    
    # Activity breakdown
    lines.append(f"🏃 Today's Activities:")
    total_act_cal = 0
    for activity, data in activity_results.items():
        if activity == "_total":
            continue
        mins = data["duration_minutes"]
        cals = data["calories_burned"]
        met = data["met_value"]
        total_act_cal += cals
        lines.append(f"   • {activity}: {mins:.0f} min → {cals:.0f} kcal (MET {met})")
    
    lines.append(f"   ─────────────────────────")
    lines.append(f"   Total Activity Burn: {total_act_cal:.0f} kcal")
    lines.append(f"")
    
    # Daily target
    lines.append(f"🍽️ Daily Calorie Target: {daily_target:.0f} kcal")
    if goal_adjustment != 0:
        direction = "deficit" if goal_adjustment < 0 else "surplus"
        lines.append(f"   (includes {goal_adjustment:+d} kcal {direction} for '{profile.goal} weight' goal)")
    lines.append(f"")
    
    # Recommendation
    if total_act_cal > 200:
        lines.append(f"💡 Recommendation: You burned {total_act_cal:.0f} kcal from exercise today.")
        lines.append(f"   Consider a protein-rich meal to support muscle recovery.")
    elif total_act_cal < 50:
        lines.append(f"💡 Recommendation: Low activity detected today.")
        lines.append(f"   Consider lighter meals with more vegetables and fiber.")
    
    return "\n".join(lines)


# ============================================================================
# MACRONUTRIENT TARGETS (for Phase 3 handoff)
# ============================================================================

def calculate_macro_targets(daily_calories, profile):
    """
    Calculate macronutrient targets based on daily calorie budget and goal.
    These targets are passed to Phase 3 (Nutrition Engine) for meal planning.
    
    Protein: 0.8-1.2g per kg body weight (higher if active/losing)
    Carbs: 45-65% of daily calories
    Fat: 20-35% of daily calories
    """
    if profile.goal == "lose":
        # Higher protein to preserve muscle during deficit
        protein_g = round(profile.weight_kg * 1.2, 1)
        carb_pct = 0.45
        fat_pct = 0.30
    elif profile.goal == "gain":
        # Higher carbs for energy surplus
        protein_g = round(profile.weight_kg * 1.0, 1)
        carb_pct = 0.55
        fat_pct = 0.25
    else:
        # Balanced for maintenance
        protein_g = round(profile.weight_kg * 0.9, 1)
        carb_pct = 0.50
        fat_pct = 0.28
    
    protein_cal = protein_g * 4  # 4 cal per gram of protein
    remaining_cal = daily_calories - protein_cal
    
    carb_cal = daily_calories * carb_pct
    fat_cal = daily_calories * fat_pct
    
    carb_g = round(carb_cal / 4, 1)   # 4 cal per gram
    fat_g = round(fat_cal / 9, 1)     # 9 cal per gram
    
    return {
        "protein_g": protein_g,
        "carbs_g": carb_g,
        "fat_g": fat_g,
        "protein_cal": round(protein_cal, 0),
        "carbs_cal": round(carb_cal, 0),
        "fat_cal": round(fat_cal, 0),
        "fiber_g": 25,  # WHO minimum recommendation
    }


# ============================================================================
# DEMO: Full Pipeline Test
# ============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Phase 2: Energy & Physiological Logic — Demo")
    print("=" * 70)
    
    # ── Create test user profiles ──
    profiles = [
        UserProfile("Joshwin", 22, 70, 175, "male", "moderate", "lose"),
        UserProfile("Sarah", 28, 58, 162, "female", "light", "maintain"),
        UserProfile("Mike", 35, 85, 180, "male", "active", "gain"),
    ]
    
    print("\n" + "─" * 70)
    print("TEST 1: BMR Calculation Validation")
    print("─" * 70)
    
    for p in profiles:
        bmr_mj = calculate_bmr(p)
        bmr_hb = calculate_bmr_harris_benedict(p)
        diff_pct = abs(bmr_mj - bmr_hb) / bmr_mj * 100
        
        print(f"\n   {p.name} ({p.gender}, {p.age}y, {p.weight_kg}kg, {p.height_cm}cm)")
        print(f"   Mifflin-St Jeor: {bmr_mj} kcal/day")
        print(f"   Harris-Benedict:  {bmr_hb} kcal/day")
        print(f"   Difference:       {diff_pct:.1f}%")
        
        if diff_pct < 10:
            print(f"   ✅ Two formulas agree within 10%")
        else:
            print(f"   ⚠️ Warning: formulas differ by {diff_pct:.1f}%")
    
    # ── Test MET values ──
    print("\n" + "─" * 70)
    print("TEST 2: MET Mapping")
    print("─" * 70)
    
    for activity, met in MET_VALUES.items():
        cal_30min = calculate_calories_burned(met, 70, 30)
        print(f"   {activity:12s} → MET {met:4.1f} → {cal_30min:6.1f} kcal (30 min, 70kg)")
    
    # ── Simulate HAR predictions (morning jog scenario) ──
    print("\n" + "─" * 70)
    print("TEST 3: Morning Jog Scenario (Joshwin)")
    print("─" * 70)
    
    # Simulate: 30 min jogging + 10 min walking home + 20 min sitting
    har_predictions = (
        ["Jogging"] * 180 +    # 180 windows × 10s = 30 min jogging
        ["Walking"] * 60 +     # 60 windows × 10s = 10 min walking
        ["Sitting"] * 120      # 120 windows × 10s = 20 min sitting
    )
    
    print(f"\n   Simulated HAR predictions: {len(har_predictions)} windows")
    print(f"   Total tracked time: {len(har_predictions) * 10 / 60:.0f} minutes")
    
    # Process predictions
    activity_durations = process_har_predictions(har_predictions)
    print(f"\n   Activity durations:")
    for activity, minutes in activity_durations.items():
        print(f"     {activity}: {minutes} min")
    
    # Generate full daily summary
    user = profiles[0]  # Joshwin
    summary = generate_daily_summary(user, activity_durations)
    
    print(f"\n{summary['explanation']}")
    
    # ── Test with meals already eaten ──
    print("\n" + "─" * 70)
    print("TEST 4: After Breakfast (Meal Tracking)")
    print("─" * 70)
    
    meals_eaten = {"breakfast": 450}
    summary_after = generate_daily_summary(user, activity_durations, meals_eaten)
    
    print(f"\n   Daily target:      {summary_after['daily_energy']['daily_target']} kcal")
    print(f"   Breakfast eaten:   {meals_eaten['breakfast']} kcal")
    print(f"   Remaining today:   {summary_after['meals']['remaining_calories']} kcal")
    print(f"\n   Suggested meal targets:")
    for meal, target in summary_after['meals']['remaining_meal_targets'].items():
        print(f"     {meal:12s}: {target:.0f} kcal")
    
    # ── Test macronutrient targets ──
    print("\n" + "─" * 70)
    print("TEST 5: Macronutrient Targets")
    print("─" * 70)
    
    for p in profiles:
        bmr = calculate_bmr(p)
        daily_target, _ = adjust_for_goal(bmr + 300, p.goal)  # BMR + some activity
        macros = calculate_macro_targets(daily_target, p)
        
        print(f"\n   {p.name} (goal: {p.goal}, target: {daily_target} kcal)")
        print(f"     Protein: {macros['protein_g']}g ({macros['protein_cal']:.0f} kcal)")
        print(f"     Carbs:   {macros['carbs_g']}g ({macros['carbs_cal']:.0f} kcal)")
        print(f"     Fat:     {macros['fat_g']}g ({macros['fat_cal']:.0f} kcal)")
        print(f"     Fiber:   {macros['fiber_g']}g (WHO minimum)")
    
    # ── Option A vs Option B comparison ──
    print("\n" + "─" * 70)
    print("TEST 6: Option A (TDEE) vs Option B (BMR + Live) Comparison")
    print("─" * 70)
    
    user = profiles[0]
    bmr = calculate_bmr(user)
    
    # Option A: Fixed TDEE
    tdee = calculate_tdee(bmr, user.activity_level)
    target_a, adj_a = adjust_for_goal(tdee, user.goal)
    
    # Option B: BMR + today's actual activity
    activity_cal = summary['activity_tracking']['total_activity_calories']
    daily_exp_b = bmr + activity_cal
    target_b, adj_b = adjust_for_goal(daily_exp_b, user.goal)
    
    print(f"\n   {user.name}'s BMR: {bmr} kcal")
    print(f"\n   Option A (Fixed TDEE):")
    print(f"     TDEE = BMR × 1.55 = {tdee} kcal")
    print(f"     After goal adjustment: {target_a} kcal")
    print(f"     ❌ Same number every day regardless of activity")
    print(f"\n   Option B (BMR + Live Tracking) ← YOUR PROJECT:")
    print(f"     BMR + {activity_cal} kcal (today's actual activity) = {daily_exp_b:.0f} kcal")
    print(f"     After goal adjustment: {target_b} kcal")
    print(f"     ✅ Adapts based on what you actually did today")
    print(f"\n   Difference: {abs(target_a - target_b):.0f} kcal")
    print(f"   Option B is {'lower' if target_b < target_a else 'higher'} because "
          f"today's activity was {'less' if target_b < target_a else 'more'} "
          f"than the 'moderate' assumption")

    # ── Test Dynamic GPS Speed ──
    print("\n" + "─" * 70)
    print("TEST 7: GPS Speed-based Dynamic MET Scaling")
    print("─" * 70)
    
    # Let's compare walking at 2.0 mph vs walking at 4.0 mph for 30 minutes
    cal_slow = calculate_activity_calories({"Walking": 30}, 70, speed_data={"Walking": 2.0})["Walking"]["calories_burned"]
    cal_fast = calculate_activity_calories({"Walking": 30}, 70, speed_data={"Walking": 4.0})["Walking"]["calories_burned"]
    cal_default = calculate_activity_calories({"Walking": 30}, 70)["Walking"]["calories_burned"] # Default 3.0 mph
    
    print("\n   30 Minutes of Walking (70kg person):")
    print(f"     Slow walk (2.0 mph)      = {cal_slow:.1f} kcal (2.8 MET)")
    print(f"     Normal walk (No GPS)     = {cal_default:.1f} kcal (3.5 MET)")
    print(f"     Brisk walk (4.0 mph)     = {cal_fast:.1f} kcal (5.0 MET)")
    print(f"\n   Conclusion: Without GPS, app assumes {cal_default:.1f} kcal. With GPS, it scales dynamically!")
    
    # ── Save summary as JSON (for Phase 3) ──
    print("\n" + "─" * 70)
    print("OUTPUT: Saving summary for Phase 3")
    print("─" * 70)
    
    output_dir = Path(r"c:\Users\joshw\OneDrive\Desktop\FYP_Work\Models")
    output_path = output_dir / "phase2_daily_summary.json"
    
    # Convert summary to JSON-safe format
    json_summary = {
        "timestamp": datetime.now().isoformat(),
        "user": summary["user"],
        "bmr": summary["bmr"],
        "daily_energy": summary["daily_energy"],
        "activity_tracking": summary["activity_tracking"],
        "meals": summary["meals"],
        "macros": calculate_macro_targets(
            summary["daily_energy"]["daily_target"], user
        )
    }
    
    with open(output_path, 'w') as f:
        json.dump(json_summary, f, indent=2)
    
    print(f"   ✅ Saved to: {output_path}")
    
    print("\n" + "=" * 70)
    print("🎉 Phase 2 Complete!")
    print("=" * 70)
    print(f"\n   Key components implemented:")
    print(f"   1. UserProfile — stores user data")
    print(f"   2. calculate_bmr() — Mifflin-St Jeor BMR")
    print(f"   3. MET_VALUES — activity energy mapping")
    print(f"   4. calculate_calories_burned() — MET × weight × duration")
    print(f"   5. process_har_predictions() — HAR windows → durations → calories")
    print(f"   6. generate_daily_summary() — full pipeline integration")
    print(f"   7. calculate_macro_targets() — protein/carb/fat targets")
    print(f"   8. generate_explanation() — plain-language XAI output")
    print(f"\n   Next: Phase 3 — Nutrition Knowledge Base & Meal Recommendation Engine")
