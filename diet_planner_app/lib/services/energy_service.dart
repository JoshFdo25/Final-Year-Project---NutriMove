/// Energy calculation service — Dart port of Phase 2 logic.
/// Implements BMR, MET-based calorie estimation, and daily summary.
library;

import '../utils/constants.dart';
import '../models/user_profile.dart';

class EnergyService {
  /// Calculate BMR using Mifflin-St Jeor equation.
  /// Returns kcal/day.
  static double calculateBmr(UserProfile profile) {
    double bmr =
        (10 * profile.weightKg) + (6.25 * profile.heightCm) - (5 * profile.age);
    if (profile.gender == 'male') {
      bmr += 5;
    } else {
      bmr -= 161;
    }
    return bmr;
  }

  /// Get MET value for an activity.
  static double getMetValue(String activity) {
    return metValues[activity] ?? 1.3;
  }

  /// Calculate calories burned for a specific activity.
  /// Formula: Calories = MET × Weight(kg) × Duration(hours)
  static double calculateCaloriesBurned(
      double met, double weightKg, double durationMinutes) {
    return met * weightKg * (durationMinutes / 60.0);
  }

  /// Calculate total calories from activity durations.
  /// activityDurations: {activityName: durationMinutes}
  static Map<String, dynamic> calculateActivityCalories(
      Map<String, double> activityDurations, double weightKg) {
    final results = <String, dynamic>{};
    double totalCalories = 0;
    double totalMinutes = 0;

    for (final entry in activityDurations.entries) {
      final met = getMetValue(entry.key);
      final calories = calculateCaloriesBurned(met, weightKg, entry.value);
      results[entry.key] = {
        'durationMinutes': entry.value,
        'metValue': met,
        'caloriesBurned': calories,
      };
      totalCalories += calories;
      totalMinutes += entry.value;
    }

    results['_total'] = {
      'totalMinutes': totalMinutes,
      'totalCalories': totalCalories,
    };

    return results;
  }

  /// Calculate TDEE (fallback method).
  static double calculateTdee(double bmr, String activityLevel) {
    final multiplier = activityMultipliers[activityLevel] ?? 1.55;
    return bmr * multiplier;
  }

  /// Adjust daily calories for goal.
  /// Returns (adjusted calories, adjustment amount).
  static (double, int) adjustForGoal(double dailyCalories, String goal) {
    final adjustment = goalAdjustments[goal] ?? 0;
    double adjusted = dailyCalories + adjustment;
    // Safety: never below 1200 kcal
    if (adjusted < 1200) adjusted = 1200;
    return (adjusted, adjustment);
  }

  /// Process HAR predictions into activity durations.
  /// Each prediction is one 10-second window.
  static Map<String, double> processHarPredictions(
      List<String> predictions, {int windowSeconds = 10}) {
    final counts = <String, int>{};
    for (final pred in predictions) {
      final activity = harCodeMap[pred] ?? pred;
      counts[activity] = (counts[activity] ?? 0) + 1;
    }

    final durations = <String, double>{};
    for (final entry in counts.entries) {
      durations[entry.key] = (entry.value * windowSeconds) / 60.0;
    }
    return durations;
  }

  /// Calculate macronutrient targets.
  static Map<String, double> calculateMacroTargets(
      double dailyCalories, UserProfile profile) {
    double proteinPerKg;
    double carbPct;
    double fatPct;

    switch (profile.goal) {
      case 'lose':
        proteinPerKg = 1.2;
        carbPct = 0.45;
        fatPct = 0.30;
        break;
      case 'gain':
        proteinPerKg = 1.0;
        carbPct = 0.55;
        fatPct = 0.25;
        break;
      default: // maintain
        proteinPerKg = 0.9;
        carbPct = 0.50;
        fatPct = 0.28;
    }

    final proteinG = profile.weightKg * proteinPerKg;
    final carbsG = (dailyCalories * carbPct) / 4; // 4 cal/g
    final fatG = (dailyCalories * fatPct) / 9; // 9 cal/g

    return {
      'proteinG': proteinG,
      'carbsG': carbsG,
      'fatG': fatG,
      'fiberG': 25, // WHO minimum
    };
  }

  /// Generate a complete daily summary.
  static Map<String, dynamic> generateDailySummary(
    UserProfile profile,
    Map<String, double> activityDurations, {
    Map<String, double>? mealsEaten,
  }) {
    final meals = mealsEaten ?? {};

    // BMR
    final bmr = calculateBmr(profile);

    // Activity calories (Option B)
    final activityResults =
        calculateActivityCalories(activityDurations, profile.weightKg);
    final activityCalories =
        (activityResults['_total'] as Map)['totalCalories'] as double;

    // Today's expenditure
    final dailyExpenditure = bmr + activityCalories;

    // Goal adjustment
    final (dailyTarget, goalAdj) =
        adjustForGoal(dailyExpenditure, profile.goal);

    // Consumed
    final totalConsumed = meals.values.fold(0.0, (a, b) => a + b);
    final remaining = dailyTarget - totalConsumed;

    // Remaining meal targets
    final remainingMeals = <String, double>{};
    final distribution = getMealDistribution(profile.goal);
    for (final entry in distribution.entries) {
      if (!meals.containsKey(entry.key)) {
        remainingMeals[entry.key] = dailyTarget * entry.value;
      }
    }

    // Macros
    final macros = calculateMacroTargets(dailyTarget, profile);

    return {
      'bmr': bmr,
      'activityCalories': activityCalories,
      'dailyExpenditure': dailyExpenditure,
      'goalAdjustment': goalAdj,
      'dailyTarget': dailyTarget,
      'totalConsumed': totalConsumed,
      'remaining': remaining,
      'remainingMeals': remainingMeals,
      'macros': macros,
      'activities': activityResults,
    };
  }
}
