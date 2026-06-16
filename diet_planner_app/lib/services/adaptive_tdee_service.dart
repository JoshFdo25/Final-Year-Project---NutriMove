/// Adaptive TDEE Service — Rolling activity pattern learner.
///
/// Uses the user's actual activity history (from the background tracker)
/// to predict today's calorie expenditure more accurately each day.
///
/// Day 1:  Falls back to generic activity multiplier
/// Day 2:  Uses yesterday's actual burn
/// Day 7+: Uses 7-day rolling average
/// Day 30+: Uses day-of-week patterns (weekday vs weekend)
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../utils/constants.dart';
import 'energy_service.dart';

class AdaptiveTdeeService {
  /// Key format for storing daily calorie burn: "2026-6-11_calories"
  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}_calories';

  /// Store today's actual calorie burn (called at end of day or on app resume).
  static Future<void> recordDailyBurn(double calories) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    await prefs.setDouble(_dateKey(today), calories);
  }

  /// Retrieve last N days of stored activity burns.
  static Future<List<double>> _getRecentBurns(int days) async {
    final prefs = await SharedPreferences.getInstance();
    final burns = <double>[];
    for (int i = 1; i <= days; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final burn = prefs.getDouble(_dateKey(date));
      if (burn != null && burn > 0) {
        burns.add(burn);
      }
    }
    return burns;
  }

  /// Retrieve burns for the same day-of-week over the last N weeks.
  static Future<List<double>> _getDayOfWeekBurns(int weekday, int weeks) async {
    final prefs = await SharedPreferences.getInstance();
    final burns = <double>[];
    final today = DateTime.now();
    for (int w = 1; w <= weeks; w++) {
      final date = today.subtract(Duration(days: w * 7));
      // Adjust to match the target weekday
      final diff = (date.weekday - weekday) % 7;
      final targetDate = date.subtract(Duration(days: diff));
      final burn = prefs.getDouble(_dateKey(targetDate));
      if (burn != null && burn > 0) {
        burns.add(burn);
      }
    }
    return burns;
  }

  /// Predict today's total calorie expenditure.
  /// Becomes more accurate each day as history accumulates.
  static Future<double> getPredictedDailyTarget(UserProfile profile) async {
    final bmr = EnergyService.calculateBmr(profile);

    // Try day-of-week pattern first (30+ days of data)
    final dowBurns = await _getDayOfWeekBurns(DateTime.now().weekday, 4);
    double predictedBurn;

    if (dowBurns.length >= 3) {
      // Enough day-of-week data — use it for pattern-aware prediction
      predictedBurn = dowBurns.reduce((a, b) => a + b) / dowBurns.length;
    } else {
      // Fall back to rolling 7-day average
      final recentBurns = await _getRecentBurns(7);
      if (recentBurns.isNotEmpty) {
        predictedBurn = recentBurns.reduce((a, b) => a + b) / recentBurns.length;
      } else {
        // No history — use generic activity multiplier
        final multiplier = activityMultipliers[profile.activityLevel] ?? 1.55;
        predictedBurn = bmr * (multiplier - 1);
      }
    }

    final dailyExpenditure = bmr + predictedBurn;
    final (dailyTarget, _) =
        EnergyService.adjustForGoal(dailyExpenditure, profile.goal);
    return dailyTarget;
  }

  /// Get the predicted burn for today (for display purposes).
  static Future<double> getPredictedBurn(UserProfile profile) async {
    final bmr = EnergyService.calculateBmr(profile);
    final target = await getPredictedDailyTarget(profile);
    final goalAdj = goalAdjustments[profile.goal] ?? 0;
    return target - bmr - goalAdj;
  }

  /// Get confidence level based on available data.
  static Future<String> getConfidenceLevel() async {
    final recentBurns = await _getRecentBurns(7);
    final dowBurns = await _getDayOfWeekBurns(DateTime.now().weekday, 4);

    if (dowBurns.length >= 3) {
      return 'high'; // Week-pattern aware
    } else if (recentBurns.length >= 5) {
      return 'good'; // Solid rolling average
    } else if (recentBurns.isNotEmpty) {
      return 'learning'; // Some data
    } else {
      return 'initial'; // No data yet
    }
  }
}
