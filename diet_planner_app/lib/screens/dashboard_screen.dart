import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/auth_provider.dart';
import '../services/energy_service.dart';
import '../services/meal_recommendation_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, Map<String, dynamic>> _loggedMeals = {};

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
    MealRecommendationService.mealUpdateNotifier.addListener(_loadRecommendations);
  }

  Future<void> _loadRecommendations() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final profile = auth.userProfile;
    if (profile == null) return;
    try {
      final logged = await MealRecommendationService.getLoggedMeals();
      if (mounted) {
        setState(() {
          _loggedMeals = logged;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  @override
  void dispose() {
    MealRecommendationService.mealUpdateNotifier.removeListener(_loadRecommendations);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.userProfile;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Calculate energy data
    final bmr = EnergyService.calculateBmr(profile);
    final activityDurations = <String, double>{};
    final summary = EnergyService.generateDailySummary(
      profile,
      activityDurations,
    );
    final activityCalories = context.watch<TrackingProvider>().totalCalories;

    // Add real activity calories to the baseline target to get the truly adaptive target
    final adaptiveDailyTarget =
        (summary['dailyTarget'] as double) + activityCalories;
    // Recalculate macro targets based on the ADAPTIVE daily target (so targets expand as you run)
    final macros = EnergyService.calculateMacroTargets(
      adaptiveDailyTarget,
      profile,
    );

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
    final actualRemaining = (adaptiveDailyTarget - customTotalConsumed)
        .clamp(0, double.infinity)
        .toDouble();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Hi, ${profile.name.split(' ').first}!'),
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).scaffoldBackgroundColor,
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 1.0),
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
          left: 16,
          right: 16,
          bottom: 16,
        ),
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
                                  ? (customTotalConsumed / adaptiveDailyTarget)
                                        .clamp(0, 1)
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
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
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
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Energy Overview',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      context,
                      'BMR (Resting)',
                      '${bmr.toStringAsFixed(0)} kcal',
                      Icons.bedtime,
                    ),
                    _buildInfoRow(
                      context,
                      'Activity Burn',
                      '${activityCalories.toStringAsFixed(0)} kcal',
                      Icons.directions_run,
                    ),
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
                    Row(
                      children: [
                        const Icon(Icons.pie_chart, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Macronutrient Targets',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildMacroBar(
                      context,
                      'Protein',
                      macros['proteinG'] ?? 0.0,
                      consumedProtein,
                      Colors.red.shade400,
                    ),
                    const SizedBox(height: 12),
                    _buildMacroBar(
                      context,
                      'Carbs',
                      macros['carbsG'] ?? 0.0,
                      consumedCarbs,
                      Colors.amber.shade600,
                    ),
                    const SizedBox(height: 12),
                    _buildMacroBar(
                      context,
                      'Fat',
                      macros['fatG'] ?? 0.0,
                      consumedFat,
                      Colors.blue.shade400,
                    ),
                  ],
                ),
              ),
            ),
            // ─── Dietary Tab Notice ────────────────
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('Ready to eat?'),
                subtitle: const Text(
                  'Head over to the Diet tab to plan your meals.',
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
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
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMacroBar(
    BuildContext context,
    String label,
    double target,
    double consumed,
    Color color,
  ) {
    double progress = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              '${consumed.toStringAsFixed(0)}g / ${target.toStringAsFixed(0)}g',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
