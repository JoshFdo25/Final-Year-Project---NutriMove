import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../providers/auth_provider.dart';
import '../services/energy_service.dart';
import '../services/meal_recommendation_service.dart';
import '../services/adaptive_tdee_service.dart';
import '../utils/constants.dart';
import 'meal_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _realActivityCalories = 0.0;
  StreamSubscription<Map<String, dynamic>?>? _serviceListener;
  Map<String, MealRecommendation>? _dailyMeals;
  Map<String, Map<String, dynamic>> _loggedMeals = {};
  bool _loadingMeals = true;

  @override
  void initState() {
    super.initState();
    _listenToTracker();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final profile = auth.userProfile;
    if (profile == null) return;
    try {
      final logged = await MealRecommendationService.getLoggedMeals();
      final meals = await MealRecommendationService.recommendDailyMeals(
        profile: profile,
      );
      if (mounted) {
        setState(() { 
          _loggedMeals = logged;
          _dailyMeals = meals; 
          _loadingMeals = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMeals = false);
    }
  }

  void _listenToTracker() {
    final service = FlutterBackgroundService();
    _serviceListener = service.on('update').listen((event) {
      if (event != null && mounted) {
        final cals = (event['calories'] ?? 0.0).toDouble();
        setState(() {
          _realActivityCalories = cals;
        });
        // Feed adaptive TDEE learner with latest burn data
        AdaptiveTdeeService.recordDailyBurn(cals);
      }
    });
  }

  @override
  void dispose() {
    _serviceListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.userProfile;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Calculate energy data
    final bmr = EnergyService.calculateBmr(profile);
    final activityDurations = <String, double>{};
    final summary = EnergyService.generateDailySummary(
      profile,
      activityDurations,
    );
    final activityCalories = _realActivityCalories; // Live stream instead of dummy!
    
    // Add real activity calories to the baseline target to get the truly adaptive target
    final adaptiveDailyTarget = (summary['dailyTarget'] as double) + activityCalories;
    final totalConsumed = summary['totalConsumed'] as double;
    
    // Recalculate macro targets based on the ADAPTIVE daily target (so targets expand as you run)
    final macros = EnergyService.calculateMacroTargets(adaptiveDailyTarget, profile);
    
    final remaining = (adaptiveDailyTarget - totalConsumed).clamp(0, double.infinity).toDouble();

    double consumedProtein = 0.0;
    double consumedCarbs = 0.0;
    double consumedFat = 0.0;
    double customTotalConsumed = 0.0;

    for (var meal in _loggedMeals.values) {
      consumedProtein += (meal['proteinTotal'] ?? 0.0).toDouble();
      consumedCarbs += (meal['carbsTotal'] ?? 0.0).toDouble();
      consumedFat += (meal['fatTotal'] ?? 0.0).toDouble();
      customTotalConsumed += (meal['totalCalories'] ?? 0.0).toDouble();
    }
    
    // Override the generic generated totalConsumed with the actual logged calories
    final actualRemaining = (adaptiveDailyTarget - customTotalConsumed).clamp(0, double.infinity).toDouble();
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${profile.name.split(' ').first}! 👋'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Calorie Ring Card ─────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Daily Calorie Budget',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: CircularProgressIndicator(
                              value: adaptiveDailyTarget > 0
                                  ? (customTotalConsumed / adaptiveDailyTarget).clamp(0, 1)
                                  : 0,
                              strokeWidth: 12,
                              backgroundColor: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                customTotalConsumed > adaptiveDailyTarget
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  actualRemaining.toStringAsFixed(0),
                                  style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                'kcal remaining',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCalorieStat(
                          context,
                          'Target',
                          adaptiveDailyTarget.toStringAsFixed(0),
                          Icons.flag,
                          Colors.green,
                        ),
                        _buildCalorieStat(
                          context,
                          'Consumed',
                          customTotalConsumed.toStringAsFixed(0),
                          Icons.restaurant,
                          Colors.orange,
                        ),
                        _buildCalorieStat(
                          context,
                          'Burned',
                          activityCalories.toStringAsFixed(0),
                          Icons.local_fire_department,
                          Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── BMR & Energy Info ─────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔥 Energy Overview',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(context, 'BMR (Resting)',
                        '${bmr.toStringAsFixed(0)} kcal', Icons.bedtime),
                    _buildInfoRow(
                        context,
                        'Activity Burn',
                        '${activityCalories.toStringAsFixed(0)} kcal',
                        Icons.directions_run),
                    _buildInfoRow(
                      context,
                      'Goal',
                      profile.goal == 'lose'
                          ? 'Lose weight (-500 kcal)'
                          : profile.goal == 'gain'
                              ? 'Gain weight (+300 kcal)'
                              : 'Maintain weight',
                      Icons.track_changes,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Macronutrient Targets ─────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📊 Macronutrient Targets',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildMacroBar(context, 'Protein', macros['proteinG'] ?? 0.0,
                        consumedProtein, Colors.red.shade400),
                    const SizedBox(height: 12),
                    _buildMacroBar(context, 'Carbs', macros['carbsG'] ?? 0.0,
                        consumedCarbs, Colors.amber.shade600),
                    const SizedBox(height: 12),
                    _buildMacroBar(context, 'Fat', macros['fatG'] ?? 0.0,
                        consumedFat, Colors.blue.shade400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Meal Slots ────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '🍽️ Today\'s Meals',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        if (_loadingMeals)
                          const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () {
                              setState(() => _loadingMeals = true);
                              _loadRecommendations();
                            },
                            tooltip: 'Regenerate meals',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...[
                      ('breakfast', 'Breakfast', '🌅'),
                      ('lunch', 'Lunch', '☀️'),
                      ('dinner', 'Dinner', '🌙'),
                      ('snack', 'Snacks', '🍎'),
                    ].map((entry) {
                      final distribution = getMealDistribution(profile.goal);
                      final ratio = distribution[entry.$1] ?? 0.25;
                      return _buildAiMealSlot(
                        context, entry.$1, entry.$2, entry.$3,
                        adaptiveDailyTarget * ratio,
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Start tracking button removed: Managed centrally by MainWrapper
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieStat(BuildContext context, String label, String value,
      IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
      BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroBar(BuildContext context, String label, double target,
      double consumed, Color color) {
    double progress = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${consumed.toStringAsFixed(0)}g / ${target.toStringAsFixed(0)}g',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildAiMealSlot(BuildContext context, String mealKey,
      String displayName, String emoji, double targetCal) {
    final isLogged = _loggedMeals.containsKey(mealKey);
    final loggedData = _loggedMeals[mealKey];
    
    final rec = _dailyMeals?[mealKey];
    final hasRec = rec != null && rec.foods.isNotEmpty;
    
    String subtitleText;
    if (isLogged) {
      subtitleText = '${(loggedData?['totalCalories'] ?? 0.0).toStringAsFixed(0)} kcal • Eaten';
    } else if (hasRec) {
      final preview = rec.foods.take(2).map((f) => f.food.name.split(',').first).join(', ');
      subtitleText = '${rec.totalCalories.toStringAsFixed(0)} kcal • $preview';
    } else {
      subtitleText = 'Target: ${targetCal.toStringAsFixed(0)} kcal';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(emoji, style: const TextStyle(fontSize: 28)),
      title: Text(displayName),
      subtitle: Text(
        subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: isLogged ? Colors.green : Colors.grey.shade600),
      ),
      trailing: isLogged
          ? const Icon(Icons.check_circle, color: Colors.green, size: 24)
          : hasRec
              ? Icon(Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : _loadingMeals
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
      onTap: () {
        if (isLogged) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meal already logged!')),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MealDetailScreen(
              mealName: displayName,
              mealKey: mealKey,
              emoji: emoji,
              targetCalories: targetCal,
              recommendation: rec,
            ),
          ),
        ).then((_) => _loadRecommendations()); // Refresh after returning
      },
    );
  }
}
