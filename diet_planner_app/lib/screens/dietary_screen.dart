import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../providers/auth_provider.dart';
import '../services/energy_service.dart';
import '../services/meal_recommendation_service.dart';
import '../utils/constants.dart';
import 'meal_detail_screen.dart';

class DietaryScreen extends StatefulWidget {
  const DietaryScreen({super.key});

  @override
  State<DietaryScreen> createState() => _DietaryScreenState();
}

class _DietaryScreenState extends State<DietaryScreen> {
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

  void _listenToTracker() {
    final service = FlutterBackgroundService();
    _serviceListener = service.on('update').listen((event) {
      if (event != null && mounted) {
        final cals = (event['calories'] ?? 0.0).toDouble();
        setState(() {
          _realActivityCalories = cals;
        });
      }
    });
  }

  Future<void> _loadRecommendations() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final profile = auth.userProfile;
    if (profile == null) return;
    
    final summary = EnergyService.generateDailySummary(profile, <String, double>{});
    final adaptiveDailyTarget = (summary['dailyTarget'] as double) + _realActivityCalories;

    try {
      final logged = await MealRecommendationService.getLoggedMeals();
      final meals = await MealRecommendationService.recommendDailyMeals(
        profile: profile,
        customDailyTarget: adaptiveDailyTarget,
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

  @override
  void dispose() {
    _serviceListener?.cancel();
    super.dispose();
  }

  Widget _buildAiMealSlot(BuildContext context, String mealKey,
      String displayName, IconData icon, double targetCal) {
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
      leading: Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
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
              targetCalories: targetCal,
              recommendation: rec,
            ),
          ),
        ).then((_) => _loadRecommendations()); // Refresh after returning
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.userProfile;

    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final summary = EnergyService.generateDailySummary(
      profile,
      <String, double>{},
    );
    final adaptiveDailyTarget = (summary['dailyTarget'] as double) + _realActivityCalories;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Diet Planner'),
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
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.95),
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
            Row(
              children: [
                Row(
                  children: [
                    const Icon(Icons.restaurant, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Today\'s Plan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
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
            const SizedBox(height: 16),
            ...[
              ('breakfast', 'Breakfast', Icons.breakfast_dining),
              ('lunch', 'Lunch', Icons.lunch_dining),
              ('dinner', 'Dinner', Icons.dinner_dining),
              ('snack', 'Snacks', Icons.apple),
            ].map((entry) {
              final distribution = getMealDistribution(profile.goal);
              final ratio = distribution[entry.$1] ?? 0.25;
              return _buildAiMealSlot(
                context, entry.$1, entry.$2, entry.$3,
                adaptiveDailyTarget * ratio,
              );
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
