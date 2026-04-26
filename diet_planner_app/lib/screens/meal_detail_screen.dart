import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/meal_recommendation_service.dart';
import '../services/preference_learning_service.dart';

class MealDetailScreen extends StatefulWidget {
  final String mealName;
  final String mealKey;
  final String emoji;
  final double targetCalories;
  final MealRecommendation? recommendation;

  const MealDetailScreen({
    super.key,
    required this.mealName,
    required this.mealKey,
    required this.emoji,
    required this.targetCalories,
    this.recommendation,
  });

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  MealRecommendation? _rec;
  bool _loading = false;
  bool _accepted = false;
  int? _rating;
  final List<String> _skipFoodIds = [];

  @override
  void initState() {
    super.initState();
    _rec = widget.recommendation;
    if (_rec == null || _rec!.foods.isEmpty) {
      _regenerate();
    }
  }

  Future<void> _regenerate() async {
    setState(() => _loading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final profile = auth.userProfile;
    if (profile == null) return;

    final rec = await MealRecommendationService.recommendMeal(
      profile: profile,
      mealType: widget.mealKey,
      skipFoodIds: _skipFoodIds,
    );
    if (mounted) {
      setState(() {
        _rec = rec;
        _loading = false;
        _accepted = false;
        _rating = null;
      });
    }
  }

  Future<void> _acceptMeal() async {
    if (_rec == null) return;
    setState(() => _accepted = true);

    // Record positive feedback
    await PreferenceLearningService.recordFeedback(
      type: FeedbackType.accept,
      mealType: widget.mealKey,
      foodGroups: _rec!.foods.map((f) => f.food.foodGroup).toList(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Meal accepted! Your preferences are learning.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _skipFood(RecommendedFood food) async {
    _skipFoodIds.add(food.food.id);
    await _regenerate();
  }

  Future<void> _blockFood(RecommendedFood food) async {
    await PreferenceLearningService.blockFood(food.food.name);
    await PreferenceLearningService.recordFeedback(
      type: FeedbackType.block,
      mealType: widget.mealKey,
      foodGroups: [food.food.foodGroup],
    );
    _skipFoodIds.add(food.food.id);
    await _regenerate();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚫 "${food.food.name}" will never be recommended again'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await PreferenceLearningService.unblockFood(food.food.name);
              _skipFoodIds.remove(food.food.id);
              _regenerate();
            },
          ),
        ),
      );
    }
  }

  Future<void> _rateMeal(int rating) async {
    if (_rec == null) return;
    setState(() => _rating = rating);

    await PreferenceLearningService.recordFeedback(
      type: FeedbackType.rate,
      mealType: widget.mealKey,
      foodGroups: _rec!.foods.map((f) => f.food.foodGroup).toList(),
      rating: rating.toDouble(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⭐ Rated $rating/5 — Thanks for the feedback!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.emoji} ${widget.mealName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _regenerate,
            tooltip: 'Regenerate meal',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating AI recommendation...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Budget Card ───────────────────────
                  Card(
                    color: primaryColor.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Text(widget.emoji,
                              style: const TextStyle(fontSize: 40)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.mealName} Budget',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.targetCalories.toStringAsFixed(0)} kcal target • '
                                  '${_rec?.totalCalories.toStringAsFixed(0) ?? "0"} kcal planned',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── AI Banner ─────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.shade100,
                          Colors.amber.shade50,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AI-recommended based on your calorie budget, dietary preference, and learned habits',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ─── Recommended Foods ─────────────────
                  if (_rec != null && _rec!.foods.isNotEmpty) ...[
                    Text(
                      'Recommended Foods',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    ..._rec!.foods.map(
                        (rf) => _buildFoodCard(context, rf, isDark)),

                    const SizedBox(height: 16),

                    // ─── Macro Summary ────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📊 Meal Macros',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            _buildMacroRow(
                              'Protein',
                              '${_rec!.proteinTotal.toStringAsFixed(1)}g',
                              Colors.red.shade400,
                            ),
                            const SizedBox(height: 10),
                            _buildMacroRow(
                              'Carbs',
                              '${_rec!.carbsTotal.toStringAsFixed(1)}g',
                              Colors.amber.shade600,
                            ),
                            const SizedBox(height: 10),
                            _buildMacroRow(
                              'Fat',
                              '${_rec!.fatTotal.toStringAsFixed(1)}g',
                              Colors.blue.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Recipe Match ─────────────────────
                    if (_rec!.matchingRecipe != null) ...[
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.restaurant_menu,
                                      color: Colors.green.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Recipe Match',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _rec!.matchingRecipe!.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ingredients: ${_rec!.matchingRecipe!.ingredients.map((i) => i['name']).take(5).join(', ')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── Action Buttons ──────────────────
                    if (!_accepted) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _acceptMeal,
                              icon: const Icon(Icons.check),
                              label: const Text('Accept Meal'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _regenerate,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Regenerate'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ─── Star Rating (after accept) ──────
                    if (_accepted) ...[
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 32),
                              const SizedBox(height: 8),
                              const Text(
                                'Meal Accepted!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('How would you rate this meal?'),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(5, (i) {
                                  final star = i + 1;
                                  return IconButton(
                                    icon: Icon(
                                      star <= (_rating ?? 0)
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 32,
                                    ),
                                    onPressed: () => _rateMeal(star),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ─── XAI Explanation ──────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    color: Colors.amber.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Why was this recommended?',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _rec!.explanation,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Empty state
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.no_food,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No recommendations available',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _regenerate,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildFoodCard(
      BuildContext context, RecommendedFood rf, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Food group icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _groupColor(rf.food.foodGroup).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _groupIcon(rf.food.foodGroup),
                    color: _groupColor(rf.food.foodGroup),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rf.food.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${rf.portionAmount.toStringAsFixed(1).replaceAll(RegExp(r"\\.0$"), "")} ${rf.portionUnit.trim()} (${rf.portionGrams.toStringAsFixed(0)}g) • '
                        '${rf.portionCalories.toStringAsFixed(0)} kcal',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 18, color: Colors.grey.shade500),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'skip',
                      child: Row(
                        children: [
                          Icon(Icons.close, size: 18),
                          SizedBox(width: 8),
                          Text('Not now'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Never recommend',
                              style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'skip') _skipFood(rf);
                    if (action == 'block') _blockFood(rf);
                  },
                ),
              ],
            ),
            // Mini explanation
            if (rf.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rf.explanation,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            // Mini macro row
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMiniMacro('P',
                    '${(rf.food.protein * rf.portionGrams / 100).toStringAsFixed(1)}g',
                    Colors.red.shade400),
                const SizedBox(width: 16),
                _buildMiniMacro('C',
                    '${(rf.food.carbs * rf.portionGrams / 100).toStringAsFixed(1)}g',
                    Colors.amber.shade600),
                const SizedBox(width: 16),
                _buildMiniMacro('F',
                    '${(rf.food.fat * rf.portionGrams / 100).toStringAsFixed(1)}g',
                    Colors.blue.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMacro(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMacroRow(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value, style: TextStyle(color: Colors.grey.shade700)),
      ],
    );
  }

  Color _groupColor(String group) {
    return switch (group) {
      'cereals' => Colors.amber.shade700,
      'protein' => Colors.red.shade400,
      'legumes' => Colors.brown.shade400,
      'vegetables' => Colors.green.shade600,
      'fruits' => Colors.orange.shade600,
      'dairy' => Colors.blue.shade300,
      'fats_oils' => Colors.yellow.shade700,
      'sweets' => Colors.pink.shade300,
      'beverages' => Colors.cyan.shade400,
      _ => Colors.grey.shade500,
    };
  }

  IconData _groupIcon(String group) {
    return switch (group) {
      'cereals' => Icons.grain,
      'protein' => Icons.egg,
      'legumes' => Icons.spa,
      'vegetables' => Icons.eco,
      'fruits' => Icons.apple,
      'dairy' => Icons.water_drop,
      'fats_oils' => Icons.opacity,
      'sweets' => Icons.cake,
      'beverages' => Icons.local_cafe,
      _ => Icons.restaurant,
    };
  }
}
