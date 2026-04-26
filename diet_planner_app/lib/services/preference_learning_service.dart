/// Preference Learning Service — Contextual Bandit RL.
///
/// Learns from user feedback (accept/skip/block/rate) to personalize
/// future food recommendations. Maintains a lightweight weight matrix
/// that adjusts per food category based on context.
///
/// Runs entirely on-device in Dart — no TFLite needed.
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Feedback signal types from the UI.
enum FeedbackType {
  accept,    // User accepted the meal       → +1.0
  swap,      // User swapped a food item     → -0.3 for old, +0.5 for new
  skip,      // User skipped entire meal     → -0.5 to all items
  block,     // User blocked a food forever  → -2.0
  rate,      // User rated meal 1-5 stars    → (rating - 3) / 2
}

class PreferenceLearningService {
  static const String _weightsKey = 'preference_weights';
  static const String _blockedKey = 'blocked_foods';
  static const double _learningRate = 0.1;

  /// All food groups tracked by the bandit
  static const List<String> foodGroups = [
    'cereals', 'protein', 'legumes', 'vegetables', 'fruits',
    'dairy', 'fats_oils', 'sweets', 'beverages', 'condiments',
    'snacks', 'other',
  ];

  /// Context buckets: meal_type × goal
  static const List<String> mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];
  static const List<String> goals = ['lose', 'maintain', 'gain'];

  /// Load current preference weights.
  /// Returns a nested map: {meal_type: {food_group: weight}}
  /// Default weight is 1.0 (neutral).
  static Future<Map<String, Map<String, double>>> loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_weightsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.map((mt, groups) => MapEntry(
          mt,
          (groups as Map<String, dynamic>).map(
            (g, w) => MapEntry(g, (w as num).toDouble()),
          ),
        ));
      } catch (_) {
        // Corrupted data — reset
      }
    }
    // Initialize default weights (all 1.0)
    return _defaultWeights();
  }

  static Map<String, Map<String, double>> _defaultWeights() {
    final weights = <String, Map<String, double>>{};
    for (final mt in mealTypes) {
      weights[mt] = {};
      for (final fg in foodGroups) {
        weights[mt]![fg] = 1.0;
      }
    }
    return weights;
  }

  /// Save weights to SharedPreferences.
  static Future<void> _saveWeights(
      Map<String, Map<String, double>> weights) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weightsKey, jsonEncode(weights));
  }

  /// Get the preference multiplier for a food in a given context.
  /// Returns a value around 1.0 (higher = more preferred).
  static Future<double> getPreferenceScore(
      String foodGroup, String mealType) async {
    final weights = await loadWeights();
    return weights[mealType]?[foodGroup] ?? 1.0;
  }

  /// Record user feedback and update weights.
  static Future<void> recordFeedback({
    required FeedbackType type,
    required String mealType,
    required List<String> foodGroups,
    double? rating, // Only used for FeedbackType.rate
    String? swappedFoodGroup, // The food that was chosen as replacement
  }) async {
    final weights = await loadWeights();
    final mealWeights = weights[mealType] ?? {};

    switch (type) {
      case FeedbackType.accept:
        for (final fg in foodGroups) {
          mealWeights[fg] = _clamp(
            (mealWeights[fg] ?? 1.0) + _learningRate * 1.0,
          );
        }
        break;

      case FeedbackType.swap:
        // Negative signal for all original items
        for (final fg in foodGroups) {
          mealWeights[fg] = _clamp(
            (mealWeights[fg] ?? 1.0) + _learningRate * -0.3,
          );
        }
        // Positive signal for the chosen replacement
        if (swappedFoodGroup != null) {
          mealWeights[swappedFoodGroup] = _clamp(
            (mealWeights[swappedFoodGroup] ?? 1.0) + _learningRate * 0.5,
          );
        }
        break;

      case FeedbackType.skip:
        for (final fg in foodGroups) {
          mealWeights[fg] = _clamp(
            (mealWeights[fg] ?? 1.0) + _learningRate * -0.5,
          );
        }
        break;

      case FeedbackType.block:
        for (final fg in foodGroups) {
          mealWeights[fg] = _clamp(
            (mealWeights[fg] ?? 1.0) + _learningRate * -2.0,
          );
        }
        break;

      case FeedbackType.rate:
        if (rating != null) {
          final signal = (rating - 3) / 2; // 1→-1, 3→0, 5→1
          for (final fg in foodGroups) {
            mealWeights[fg] = _clamp(
              (mealWeights[fg] ?? 1.0) + _learningRate * signal,
            );
          }
        }
        break;
    }

    weights[mealType] = mealWeights;
    await _saveWeights(weights);
  }

  /// Clamp weights to [0.1, 3.0] to prevent extreme values.
  static double _clamp(double value) => value.clamp(0.1, 3.0);

  // ─────────────────────────────────────────────────────────
  // BLOCKED FOODS MANAGEMENT
  // ─────────────────────────────────────────────────────────

  /// Add a food to the permanent block list.
  static Future<void> blockFood(String foodName) async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList(_blockedKey) ?? [];
    if (!blocked.contains(foodName)) {
      blocked.add(foodName);
      await prefs.setStringList(_blockedKey, blocked);
    }
  }

  /// Remove a food from the block list.
  static Future<void> unblockFood(String foodName) async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList(_blockedKey) ?? [];
    blocked.remove(foodName);
    await prefs.setStringList(_blockedKey, blocked);
  }

  /// Get all blocked food names.
  static Future<List<String>> getBlockedFoods() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_blockedKey) ?? [];
  }

  /// Check if a food is blocked.
  static Future<bool> isBlocked(String foodName) async {
    final blocked = await getBlockedFoods();
    return blocked.contains(foodName);
  }

  /// Reset all preference weights to defaults.
  static Future<void> resetPreferences() async {
    await _saveWeights(_defaultWeights());
  }
}
