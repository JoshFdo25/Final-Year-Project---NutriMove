/// App-wide constants for the Diet Planner app.
library;

// ─── MET VALUES ────────────────────────────────────────────
// From Compendium of Physical Activities (Ainsworth et al., 2011)
const Map<String, double> metValues = {
  'Walking': 3.5,
  'Jogging': 7.0,
  'Sitting': 1.3,
  'Standing': 1.8,
  'Stairs': 4.0,
  'Cycling': 6.8,
  'Running': 9.8,
  'Sleeping': 0.95,
};

// ─── HAR MODEL CODES ───────────────────────────────────────
const Map<String, String> harCodeMap = {
  'A': 'Walking',
  'B': 'Jogging',
  'D': 'Sitting',
  'E': 'Standing',
};

// ─── ACTIVITY MULTIPLIERS (TDEE fallback) ──────────────────
const Map<String, double> activityMultipliers = {
  'sedentary': 1.2,
  'light': 1.375,
  'moderate': 1.55,
  'active': 1.725,
  'very_active': 1.9,
};

// ─── GOAL ADJUSTMENTS ──────────────────────────────────────
const Map<String, int> goalAdjustments = {
  'lose': -500,
  'maintain': 0,
  'gain': 300,
};

// ─── MEAL DISTRIBUTION (Goal-Aware) ────────────────────────
// Based on Young et al. (2023) chrononutrition meta-analysis
// Front-loaded eating → more weight loss (−1.23 kg, p=0.04)
const Map<String, Map<String, double>> goalAwareMealDistribution = {
  'lose': {
    'breakfast': 0.35,
    'lunch': 0.35,
    'dinner': 0.20,
    'snack': 0.10,
  },
  'maintain': {
    'breakfast': 0.30,
    'lunch': 0.35,
    'dinner': 0.25,
    'snack': 0.10,
  },
  'gain': {
    'breakfast': 0.25,
    'lunch': 0.35,
    'dinner': 0.30,
    'snack': 0.10,
  },
};

/// Returns the meal distribution ratios for a given goal.
Map<String, double> getMealDistribution(String goal) {
  return goalAwareMealDistribution[goal] ??
      goalAwareMealDistribution['maintain']!;
}

// ─── MEAL TIME RANGES ──────────────────────────────────────
// Used for context-aware meal type detection from current time
// {hour_start, hour_end} → meal_type
const List<Map<String, dynamic>> mealTimeRanges = [
  {'start': 6, 'end': 10, 'type': 'breakfast'},
  {'start': 10, 'end': 14, 'type': 'lunch'},
  {'start': 14, 'end': 17, 'type': 'snack'},
  {'start': 17, 'end': 21, 'type': 'dinner'},
  // 21-6 defaults to 'snack'
];

/// Returns the current meal type based on time of day.
String getCurrentMealType() {
  final hour = DateTime.now().hour;
  for (final range in mealTimeRanges) {
    if (hour >= range['start'] && hour < range['end']) {
      return range['type'];
    }
  }
  return 'snack'; // Late night default
}

// ─── SENSOR CONFIG ─────────────────────────────────────────
const int windowSize = 200; // 10 seconds at 20Hz
const double overlap = 0.5;
const int samplingRateHz = 20;
const int windowDurationSeconds = 10;

// ─── APP INFO ──────────────────────────────────────────────
const String appName = 'NutriMove';
const String appTagline = 'AI-Powered Diet & Fitness';
