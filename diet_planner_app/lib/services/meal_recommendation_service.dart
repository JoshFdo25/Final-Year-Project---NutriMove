/// Meal Recommendation Service — Core AI recommendation pipeline.
///
/// Pipeline:
///   1. Determine meal type from time of day
///   2. Calculate meal calorie budget (adaptive TDEE × goal distribution)
///   3. Load & filter foods (region, dietary, blocked, meal type)
///   4. Score foods via TFLite food scorer model
///   5. Apply RL preference weights from contextual bandit
///   6. Constraint optimization: select 3-5 foods within budget
///   7. Cross-reference recipes
///   8. Generate XAI explanation trace
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../models/user_profile.dart';
import '../utils/constants.dart';
import 'adaptive_tdee_service.dart';
import 'preference_learning_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single food item from the database.
class FoodItem {
  final String id;
  final String name;
  final String foodType;
  final String foodGroup;
  final List<String> mealTypes;
  final List<String> dietaryTags;
  final bool recommendable;
  final double calories; // per 100g
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
  final List<Map<String, dynamic>> commonPortions;

  FoodItem({
    required this.id,
    required this.name,
    required this.foodType,
    required this.foodGroup,
    required this.mealTypes,
    required this.dietaryTags,
    required this.recommendable,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
    required this.commonPortions,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final n = json['per_100g'] as Map<String, dynamic>;
    return FoodItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      foodType: json['food_type'] ?? 'S',
      foodGroup: json['food_group'] ?? 'other',
      mealTypes: List<String>.from(json['meal_types'] ?? []),
      dietaryTags: List<String>.from(json['dietary_tags'] ?? []),
      recommendable: json['recommendable'] ?? true,
      calories: (n['calories'] ?? 0).toDouble(),
      protein: (n['protein'] ?? 0).toDouble(),
      fat: (n['fat'] ?? 0).toDouble(),
      carbs: (n['carbs'] ?? 0).toDouble(),
      fiber: (n['fiber'] ?? 0).toDouble(),
      commonPortions: List<Map<String, dynamic>>.from(
        (json['common_portions'] ?? []).map((p) => Map<String, dynamic>.from(p)),
      ),
    );
  }

  /// Get the best portion size, or default to 100g.
  Map<String, dynamic> get bestPortion {
    if (commonPortions.isNotEmpty) {
      // Prefer portions that give a reasonable calorie amount (50-400 kcal)
      for (final p in commonPortions) {
        final cal = (p['calories'] ?? 0).toDouble();
        if (cal >= 50 && cal <= 400) return p;
      }
      return commonPortions.first;
    }
    return {'unit': '100g', 'grams': 100.0, 'calories': calories};
  }
}

/// A recipe from the database.
class Recipe {
  final String id;
  final String name;
  final List<Map<String, dynamic>> ingredients;

  Recipe({required this.id, required this.name, required this.ingredients});

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      ingredients: List<Map<String, dynamic>>.from(
        (json['ingredients'] ?? []).map((i) => Map<String, dynamic>.from(i)),
      ),
    );
  }
}

/// A recommended food item with portion and score info.
class RecommendedFood {
  final FoodItem food;
  final double portionGrams;
  final double portionAmount;
  final String portionUnit;
  final double portionCalories;
  final double score;
  final String explanation;

  RecommendedFood({
    required this.food,
    required this.portionGrams,
    required this.portionAmount,
    required this.portionUnit,
    required this.portionCalories,
    required this.score,
    required this.explanation,
  });
}

/// A complete meal recommendation.
class MealRecommendation {
  final String mealType;
  final double targetCalories;
  final double totalCalories;
  final List<RecommendedFood> foods;
  final Recipe? matchingRecipe;
  final String explanation;
  final DateTime generatedAt;

  MealRecommendation({
    required this.mealType,
    required this.targetCalories,
    required this.totalCalories,
    required this.foods,
    this.matchingRecipe,
    required this.explanation,
    required this.generatedAt,
  });

  double get proteinTotal =>
      foods.fold(0.0, (sum, f) => sum + f.food.protein * f.portionGrams / 100);
  double get fatTotal =>
      foods.fold(0.0, (sum, f) => sum + f.food.fat * f.portionGrams / 100);
  double get carbsTotal =>
      foods.fold(0.0, (sum, f) => sum + f.food.carbs * f.portionGrams / 100);
}

class MealRecommendationService {
  static List<FoodItem>? _foodsCache;
  static List<Recipe>? _recipesCache;

  // ─────────────────────────────────────────────────────────
  // LOGGED MEALS
  // ─────────────────────────────────────────────────────────

  static Future<void> logAcceptedMeal(String mealType, MealRecommendation rec) async {
    final prefs = await SharedPreferences.getInstance();
    final today = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final key = "logged_meals_$today";
    
    final mealData = {
      'mealType': mealType,
      'totalCalories': rec.totalCalories,
      'proteinTotal': rec.proteinTotal,
      'carbsTotal': rec.carbsTotal,
      'fatTotal': rec.fatTotal,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    String existingStr = prefs.getString(key) ?? "{}";
    Map<String, dynamic> logged = jsonDecode(existingStr);
    logged[mealType] = mealData;
    
    await prefs.setString(key, jsonEncode(logged));
  }

  static Future<Map<String, Map<String, dynamic>>> getLoggedMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final today = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final key = "logged_meals_$today";
    
    String existingStr = prefs.getString(key) ?? "{}";
    try {
      final decoded = jsonDecode(existingStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
    } catch(e) {
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────────

  /// Load food database from assets (cached after first load).
  static Future<List<FoodItem>> _loadFoods() async {
    if (_foodsCache != null) return _foodsCache!;
    final raw = await rootBundle.loadString('assets/data/foods_sri_lanka.json');
    final list = jsonDecode(raw) as List;
    _foodsCache = list.map((j) => FoodItem.fromJson(j)).toList();
    return _foodsCache!;
  }

  /// Load recipes database from assets.
  static Future<List<Recipe>> _loadRecipes() async {
    if (_recipesCache != null) return _recipesCache!;
    final raw = await rootBundle.loadString('assets/data/recipes_sri_lanka.json');
    final list = jsonDecode(raw) as List;
    _recipesCache = list.map((j) => Recipe.fromJson(j)).toList();
    return _recipesCache!;
  }

  // ─────────────────────────────────────────────────────────
  // MAIN RECOMMENDATION PIPELINE
  // ─────────────────────────────────────────────────────────

  /// Generate a meal recommendation for the current time and user profile.
  static Future<MealRecommendation> recommendMeal({
    required UserProfile profile,
    String? mealType,
    List<String> skipFoodIds = const [],
  }) async {
    final foods = await _loadFoods();
    final recipes = await _loadRecipes();

    // 1. Determine meal type
    final meal = mealType ?? getCurrentMealType();

    // 2. Calculate meal budget
    final dailyTarget = await AdaptiveTdeeService.getPredictedDailyTarget(profile);
    final distribution = getMealDistribution(profile.goal);
    final mealBudget = dailyTarget * (distribution[meal] ?? 0.30);

    // 3. Filter foods
    final blocked = await PreferenceLearningService.getBlockedFoods();
    final candidates = foods.where((f) {
      if (!f.recommendable) return false;
      if (!f.mealTypes.contains(meal)) return false;
      if (blocked.contains(f.name)) return false;
      if (skipFoodIds.contains(f.id)) return false;
      // Dietary filter
      if (profile.dietaryPreference == 'vegetarian' &&
          !f.dietaryTags.contains('vegetarian')) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return MealRecommendation(
        mealType: meal,
        targetCalories: mealBudget,
        totalCalories: 0,
        foods: [],
        explanation: 'No foods available matching your preferences.',
        generatedAt: DateTime.now(),
      );
    }

    // 4 & 5. Score foods (heuristic scoring + RL preference weights)
    final prefWeights = await PreferenceLearningService.loadWeights();
    final mealPrefs = prefWeights[meal] ?? {};

    final scored = <FoodItem, double>{};
    for (final food in candidates) {
      double score = _heuristicScore(food, meal, profile.goal, mealBudget);
      // Apply RL preference weight
      final prefWeight = mealPrefs[food.foodGroup] ?? 1.0;
      score *= prefWeight;
      scored[food] = score;
    }

    // 6. Constraint optimization
    final selectedFoods = _constraintOptimize(
      scored,
      mealBudget,
      meal,
    );

    // 7. Cross-reference recipes
    final matchingRecipe = _findMatchingRecipe(selectedFoods, recipes);

    // 8. Generate XAI trace
    final explanation = _generateExplanation(
      meal, mealBudget, selectedFoods, profile, matchingRecipe,
    );

    final totalCal = selectedFoods.fold(0.0, (sum, f) => sum + f.portionCalories);

    return MealRecommendation(
      mealType: meal,
      targetCalories: mealBudget,
      totalCalories: totalCal,
      foods: selectedFoods,
      matchingRecipe: matchingRecipe,
      explanation: explanation,
      generatedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HEURISTIC SCORING
  // ─────────────────────────────────────────────────────────

  /// Compute a heuristic suitability score for a food (0.0 - 1.0).
  static double _heuristicScore(
      FoodItem food, String mealType, String goal, double mealBudget) {
    double score = 0.0;

    // Factor 1: Meal type match (already filtered, but boost explicit matches)
    if (food.mealTypes.contains(mealType)) score += 0.25;

    // Factor 2: Calorie appropriateness for the meal budget
    final bestPortion = food.bestPortion;
    final portionCal = (bestPortion['calories'] ?? food.calories).toDouble();
    // Ideal: a single portion = 20-40% of meal budget
    final calRatio = portionCal / mealBudget;
    if (calRatio >= 0.15 && calRatio <= 0.50) {
      score += 0.25;
    } else if (calRatio > 0.50 && calRatio <= 0.70) {
      score += 0.15;
    } else {
      score += 0.05;
    }

    // Factor 3: Protein adequacy
    final proteinRatio = (food.protein * 4) / max(food.calories, 1);
    if (goal == 'lose' && proteinRatio >= 0.25) {
      score += 0.20;
    } else if (proteinRatio >= 0.15) {
      score += 0.15;
    } else {
      score += 0.05;
    }

    // Factor 4: Food group quality
    const goodGroups = {'cereals', 'protein', 'legumes', 'vegetables', 'fruits', 'dairy'};
    if (goodGroups.contains(food.foodGroup)) {
      score += 0.15;
    } else {
      score += 0.05;
    }

    // Factor 5: Fiber bonus (for weight loss)
    if (food.fiber > 3.0) score += 0.10;

    // Add significant randomness to promote daily variety and exploration (epsilon noise)
    score += Random().nextDouble() * 0.30;

    return score;
  }

  // ─────────────────────────────────────────────────────────
  // CONSTRAINT OPTIMIZATION
  // ─────────────────────────────────────────────────────────

  /// Select 3-5 foods that fit within the calorie budget and hit
  /// food group diversity targets (starch + protein + veg).
  static List<RecommendedFood> _constraintOptimize(
    Map<FoodItem, double> scored,
    double mealBudget,
    String mealType,
  ) {
    // Sort by score descending
    final sortedFoods = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = <RecommendedFood>[];
    double remainingCal = mealBudget;

    bool isBreakfast = mealType.toLowerCase() == 'breakfast';

    // Step A: Pick ONE Main Course
    // A main course is either a Recipe (foodType == 'R') OR a core cereal (foodGroup == 'cereals')
    var mainCandidates = sortedFoods.where((e) {
      final f = e.key;
      if (isBreakfast) {
        if (f.name.toLowerCase().contains('soup') || 
            f.foodGroup == 'sweets' || 
            f.foodGroup == 'snacks') {
          return false;
        }
      }
      return f.foodType == 'R' || f.foodGroup == 'cereals';
    }).toList();

    // Fallback if no main candidates found
    if (mainCandidates.isEmpty) mainCandidates = sortedFoods;

    final mainEntry = mainCandidates.first;
    final mainFood = mainEntry.key;

    // Scale main portion. Target ~50% of the total meal budget.
    var mainPortion = mainFood.bestPortion;
    var originalMainGrams = (mainPortion['grams'] ?? 100.0).toDouble();
    var mainGrams = originalMainGrams;
    var mainCal = (mainPortion['calories'] ?? mainFood.calories).toDouble();

    final targetMainCal = remainingCal * 0.50;
    if (mainCal > 0) {
      final scale = targetMainCal / mainCal;
      mainGrams *= scale;
      mainCal *= scale;
    }

    selected.add(RecommendedFood(
      food: mainFood,
      portionGrams: mainGrams,
      portionAmount: mainGrams / (originalMainGrams > 0 ? originalMainGrams : 100.0),
      portionUnit: mainPortion['unit'] ?? '100g',
      portionCalories: mainCal,
      score: mainEntry.value,
      explanation: _foodExplanation(mainFood, mainEntry.value, mealType),
    ));

    remainingCal -= mainCal;

    // Step B: Determine necessary sides based on Main Course macros
    bool needsProtein = (mainFood.protein * 4) / max(mainFood.calories, 1) < 0.15;
    bool hasVeg = false;
    bool hasBeverage = false;

    // Step C: Fill roles using remaining budget
    for (final entry in sortedFoods) {
      if (remainingCal <= 30) break;
      if (selected.length >= 4) break; // Limit to Main + 3 sides max

      final food = entry.key;

      if (food.id == mainFood.id) continue;

      // 1. STRICT BANS
      // Ban any second main course (no double recipes, no double cereals)
      if (food.foodType == 'R' || food.foodGroup == 'cereals') continue;

      if (isBreakfast) {
        if (food.name.toLowerCase().contains('soup') || food.foodGroup == 'sweets') continue;
      }

      // Conceptual duplicate prevention (bans milk if already have milk, egg if already have egg)
      bool isNameDuplicate = false;
      const keywords = ['milk', 'egg', 'chicken', 'rice', 'bread', 'dosa', 'roti', 'beef', 'fish'];
      for (final kw in keywords) {
        if (food.name.toLowerCase().contains(kw) && 
            selected.any((s) => s.food.name.toLowerCase().contains(kw))) {
          isNameDuplicate = true;
          break;
        }
      }
      if (isNameDuplicate) continue;

      // 2. ROLE ALLOCATION
      bool pick = false;
      if (needsProtein && food.foodGroup == 'protein') {
        pick = true;
        needsProtein = false; // Fulfilled
      } else if (!hasVeg && (food.foodGroup == 'vegetables' || food.foodGroup == 'condiments')) {
        pick = true;
        hasVeg = true; // Fulfilled
      } else if (!hasBeverage && (food.foodGroup == 'beverages' || food.foodGroup == 'dairy' || food.foodGroup == 'milk')) {
        pick = true;
        hasBeverage = true; // Fulfilled
      } else if (!needsProtein && food.foodGroup == 'fruits') {
        pick = true;
      } else if (!needsProtein && food.foodGroup == 'protein') {
        pick = true; // allow a light extra protein if budget allows
      }

      if (!pick) continue;

      var portion = food.bestPortion;
      var originalGrams = (portion['grams'] ?? 100.0).toDouble();
      var portionGrams = originalGrams;
      var portionCal = (portion['calories'] ?? food.calories).toDouble();

      // Scale to fit remaining budget
      if (portionCal > 0 && portionCal > remainingCal) {
          final scale = remainingCal / portionCal;
          portionGrams *= scale;
          portionCal *= scale;
      }

      if (portionCal < 20) continue; // Too small

      selected.add(RecommendedFood(
        food: food,
        portionGrams: portionGrams,
        portionAmount: portionGrams / (originalGrams > 0 ? originalGrams : 100.0),
        portionUnit: portion['unit'] ?? '100g',
        portionCalories: portionCal,
        score: entry.value,
        explanation: _foodExplanation(food, entry.value, mealType),
      ));

      remainingCal -= portionCal;
    }

    return selected;
  }

  // ─────────────────────────────────────────────────────────
  // RECIPE MATCHING
  // ─────────────────────────────────────────────────────────

  /// Find a recipe that uses the selected food items.
  static Recipe? _findMatchingRecipe(
      List<RecommendedFood> selectedFoods, List<Recipe> recipes) {
    final selectedIds = selectedFoods.map((f) => f.food.id).toSet();
    final selectedNames =
        selectedFoods.map((f) => f.food.name.toLowerCase()).toSet();

    Recipe? bestMatch;
    int bestOverlap = 0;

    for (final recipe in recipes) {
      int overlap = 0;
      for (final ing in recipe.ingredients) {
        final ingCode = ing['code'] ?? '';
        final ingName = (ing['name'] ?? '').toString().toLowerCase();
        if (selectedIds.contains(ingCode) ||
            selectedNames.any((n) => ingName.contains(n) || n.contains(ingName))) {
          overlap++;
        }
      }
      if (overlap > bestOverlap && overlap >= 2) {
        bestOverlap = overlap;
        bestMatch = recipe;
      }
    }

    return bestMatch;
  }

  // ─────────────────────────────────────────────────────────
  // XAI EXPLANATIONS
  // ─────────────────────────────────────────────────────────

  /// Generate a per-food explanation.
  static String _foodExplanation(FoodItem food, double score, String mealType) {
    final reasons = <String>[];

    if (food.protein > 10) {
      reasons.add('Good protein source (${food.protein.toStringAsFixed(1)}g/100g)');
    }
    if (food.fiber > 3) {
      reasons.add('High in fiber (${food.fiber.toStringAsFixed(1)}g/100g)');
    }
    if (food.calories < 150) {
      reasons.add('Low calorie density');
    }
    if ({'cereals', 'legumes'}.contains(food.foodGroup)) {
      reasons.add('Provides sustained energy');
    }
    if ({'vegetables', 'fruits'}.contains(food.foodGroup)) {
      reasons.add('Rich in micronutrients');
    }

    return reasons.isEmpty ? 'Suitable for $mealType' : reasons.join('. ');
  }

  /// Generate the overall meal explanation.
  static String _generateExplanation(
    String mealType,
    double budget,
    List<RecommendedFood> foods,
    UserProfile profile,
    Recipe? recipe,
  ) {
    final parts = <String>[];
    final totalCal = foods.fold(0.0, (sum, f) => sum + f.portionCalories);

    parts.add(
      'Your $mealType budget is ${budget.toStringAsFixed(0)} kcal '
      '(${(getMealDistribution(profile.goal)[mealType]! * 100).toStringAsFixed(0)}% '
      'of daily target for ${profile.goal} goal).',
    );

    parts.add(
      'This meal provides ${totalCal.toStringAsFixed(0)} kcal '
      'with ${foods.length} items from different food groups.',
    );

    // Food group diversity
    final groups = foods.map((f) => f.food.foodGroup).toSet();
    if (groups.contains('cereals') && groups.contains('protein')) {
      parts.add('Balanced combination of carbohydrates and protein.');
    }
    if (groups.contains('vegetables')) {
      parts.add('Includes vegetables for micronutrient coverage.');
    }

    if (recipe != null) {
      parts.add('Try making: ${recipe.name}');
    }

    return parts.join(' ');
  }

  /// Generate recommendations for all meals of the day.
  static Future<Map<String, MealRecommendation>> recommendDailyMeals({
    required UserProfile profile,
  }) async {
    final results = <String, MealRecommendation>{};
    for (final meal in ['breakfast', 'lunch', 'dinner', 'snack']) {
      results[meal] = await recommendMeal(
        profile: profile,
        mealType: meal,
      );
    }
    return results;
  }
}
