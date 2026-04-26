import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../services/energy_service.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  Map<String, double> _liveActivities = {
    'Walking': 0.0,
    'Jogging': 0.0,
    'Stairs': 0.0,
    'Sitting': 0.0,
    'Standing': 0.0,
  };
  Map<String, double> _liveCalories = {
    'Walking': 0.0,
    'Jogging': 0.0,
    'Stairs': 0.0,
    'Sitting': 0.0,
    'Standing': 0.0,
  };
  double _trackerCalories = 0.0;
  StreamSubscription<Map<String, dynamic>?>? _serviceListener;

  @override
  void initState() {
    super.initState();
    _listenToBackend();
  }

  void _listenToBackend() async {
    final service = FlutterBackgroundService();
    
    // Quick load if running
    if (await service.isRunning()) {
      setState(() {}); 
    }

    _serviceListener = service.on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _trackerCalories = event['calories'] ?? 0.0;
          if (event['activityDurations'] != null) {
            Map<dynamic, dynamic> d = event['activityDurations'];
            _liveActivities = d.map((k, v) => MapEntry(k.toString(), (v as num) / 60.0));
          }
          if (event['activityCaloriesMap'] != null) {
            Map<dynamic, dynamic> c = event['activityCaloriesMap'];
            _liveCalories = c.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
          }
        });
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
    final profile = Provider.of<AuthProvider>(context).userProfile;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bmr = EnergyService.calculateBmr(profile);

    // AI Generative Summary
    final summary = EnergyService.generateDailySummary(
      profile,
      _liveActivities,
      mealsEaten: {'breakfast': 420, 'lunch': 550},
    );
    final dailyTarget = summary['dailyTarget'] as double;
    final activityCalories = _trackerCalories; // Trusting dynamic GPS calculations natively
    final totalConsumed = summary['totalConsumed'] as double;
    final remaining = dailyTarget - activityCalories + totalConsumed; // Custom dynamic recalculation

    // Per-activity calorie breakdown (Static approximation vs GPS)
    final activityResults = summary['activities'] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Summary')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Overview Card ─────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Today\'s Overview',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCircleStat(
                            context,
                            bmr.toStringAsFixed(0),
                            'BMR',
                            Colors.purple),
                        _buildCircleStat(
                            context,
                            activityCalories.toStringAsFixed(0),
                            'Burned',
                            Colors.red),
                        _buildCircleStat(
                            context,
                            totalConsumed.toStringAsFixed(0),
                            'Eaten',
                            Colors.orange),
                        _buildCircleStat(
                            context,
                            remaining.toStringAsFixed(0),
                            'Left',
                            Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Activity Breakdown ────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏃 Activity Breakdown',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ..._liveActivities.entries.where((e) => e.value > 0).map((entry) {
                      final actName = entry.key;
                      final min = entry.value;
                      final cal = _liveCalories[actName] ?? 0.0;
                      // Dynamic GPS MET Formula: Cal = MET * Weight * H
                      // Therefore: MET = Cal / Weight / H
                      final hours = min > 0 ? (min / 60.0) : 0.001; // protect zero div
                      final dynamicMet = cal / profile.weightKg / hours;
                      
                      final totalMin = _liveActivities.values
                          .fold(0.0, (a, b) => a + b);
                      final pct = entry.value / totalMin;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _getColor(entry.key)
                                    .withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getIcon(entry.key),
                                color: _getColor(entry.key),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w600),
                                      ),
                                      Text(
                                        '${(cal).toStringAsFixed(0)} kcal',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _getColor(entry.key),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${entry.value.toStringAsFixed(0)} min • MET ${dynamicMet.toStringAsFixed(1)} (GPS Live)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 6,
                                      backgroundColor:
                                          _getColor(entry.key)
                                              .withOpacity(0.15),
                                      valueColor:
                                          AlwaysStoppedAnimation(
                                        _getColor(entry.key),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Energy Calculation ────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ Energy Calculation',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildCalcRow('BMR (Resting)', bmr, Colors.purple),
                    _buildCalcRow('+ Activity Burn',
                        activityCalories, Colors.red),
                    const Divider(),
                    _buildCalcRow('= Total Expenditure',
                        bmr + activityCalories, Colors.blue),
                    _buildCalcRow(
                      profile.goal == 'lose'
                          ? '- Goal Deficit'
                          : profile.goal == 'gain'
                              ? '+ Goal Surplus'
                              : 'Goal Adjustment',
                      profile.goal == 'lose'
                          ? -500
                          : profile.goal == 'gain'
                              ? 300
                              : 0,
                      Colors.grey,
                    ),
                    const Divider(thickness: 2),
                    _buildCalcRow(
                        '= Daily Target', dailyTarget, Colors.green,
                        bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Explanation Card (XAI) ────────────
            Card(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb,
                            color: Colors.amber.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'AI Insight',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      activityCalories > 200
                          ? 'You burned ${activityCalories.toStringAsFixed(0)} kcal from exercise today! '
                              'Your 20-minute jog was the biggest calorie burner. '
                              'Consider a protein-rich dinner to support muscle recovery.'
                          : 'Low activity detected today. Consider lighter meals '
                              'with more vegetables and fiber to stay within your target.',
                      style: const TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Option A vs B comparison ──────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📐 Why Live Tracking Matters',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.close,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Traditional (Fixed TDEE)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${EnergyService.calculateTdee(bmr, profile.activityLevel).toStringAsFixed(0)} kcal — same every day',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.green.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Our App (BMR + Live Tracking)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${dailyTarget.toStringAsFixed(0)} kcal — based on today\'s actual activity',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleStat(
      BuildContext context, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildCalcRow(String label, double value, Color color,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight:
                    bold ? FontWeight.bold : FontWeight.normal,
              )),
          Text(
            '${value >= 0 ? "" : ""}${value.toStringAsFixed(0)} kcal',
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(String activity) {
    switch (activity) {
      case 'Walking':
        return const Color(0xFF42A5F5);
      case 'Jogging':
        return const Color(0xFFEF5350);
      case 'Stairs':
        return const Color(0xFF8D6E63);
      case 'Sitting':
        return const Color(0xFFFFCA28);
      case 'Standing':
        return const Color(0xFF66BB6A);
      default:
        return Colors.grey;
    }
  }

  IconData _getIcon(String activity) {
    switch (activity) {
      case 'Walking':
        return Icons.directions_walk;
      case 'Jogging':
        return Icons.directions_run;
      case 'Stairs':
        return Icons.stairs;
      case 'Sitting':
        return Icons.chair;
      case 'Standing':
        return Icons.accessibility_new;
      default:
        return Icons.help;
    }
  }
}
