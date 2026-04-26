import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  
  bool _isTracking = false;
  bool _isIdle = false;
  int _elapsedSeconds = 0;
  String _currentActivity = 'Waiting on Sensors...';
  double _confidence = 0.0;
  double _totalCalories = 0.0;

  late AnimationController _pulseController;
  StreamSubscription<Map<String, dynamic>?>? _serviceListener;

  Map<String, int> _activitySeconds = {
    'Walking': 0, 'Jogging': 0, 'Stairs': 0, 'Sitting': 0, 'Standing': 0,
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _checkInitialState();
    _listenToBackend();
  }

  void _checkInitialState() async {
    final service = FlutterBackgroundService();
    bool running = await service.isRunning();
    if (running && mounted) {
      setState(() {
        _isTracking = true;
      });
    }
  }

  void _listenToBackend() {
    final service = FlutterBackgroundService();
    _serviceListener = service.on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _isTracking = event['isTracking'] ?? false;
          _isIdle = event['isIdle'] ?? false;
          _elapsedSeconds = event['elapsedSeconds'] ?? 0;
          _currentActivity = event['activity'] ?? 'Unknown';
          _totalCalories = event['calories'] ?? 0.0;
          _confidence = event['confidence'] ?? 0.0;
          
          if (event['activityDurations'] != null) {
            Map<dynamic, dynamic> d = event['activityDurations'];
            _activitySeconds = d.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _serviceListener?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getActivityIcon(String activity) {
    if (activity.contains('Walking')) return Icons.directions_walk;
    if (activity.contains('Jogging')) return Icons.directions_run;
    if (activity.contains('Stairs')) return Icons.stairs;
    if (activity.contains('Sitting') || activity.contains('Idle')) return Icons.chair_alt;
    if (activity.contains('Standing')) return Icons.accessibility_new;
    return Icons.help;
  }

  Color _getActivityColor(String activity) {
    if (activity.contains('Walking')) return const Color(0xFF42A5F5);
    if (activity.contains('Jogging')) return const Color(0xFFEF5350);
    if (activity.contains('Stairs')) return const Color(0xFF8D6E63);
    if (activity.contains('Sitting')) return const Color(0xFFFFCA28);
    if (activity.contains('Standing')) return const Color(0xFF66BB6A);
    if (activity.contains('Idle')) return Colors.grey;
    return Colors.grey;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activityColor = _getActivityColor(_currentActivity);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity Tracker')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ─── Current Activity Display ──────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_isTracking) ...[
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 120 + (_pulseController.value * 10),
                                height: 120 + (_pulseController.value * 10),
                                decoration: BoxDecoration(
                                  color: activityColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: activityColor.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _getActivityIcon(_currentActivity),
                                      size: 48,
                                      color: activityColor,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentActivity,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: activityColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: activityColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatDuration(_elapsedSeconds),
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w300,
                              letterSpacing: 4,
                            ),
                      ),
                    ] else ...[
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_run,
                          size: 48,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ready to Track',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uses phone sensors + AI model',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Live Stats ────────────────────────
            if (_isTracking || _elapsedSeconds > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      '🔥 Calories',
                      _totalCalories.toStringAsFixed(1),
                      'kcal',
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      '⏱️ Duration',
                      _formatDuration(_elapsedSeconds),
                      'mm:ss',
                      Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── Activity Breakdown ──────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Breakdown',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ..._activitySeconds.entries
                          .where((e) => e.value > 0)
                          .map((e) {
                        final total = _activitySeconds.values
                            .fold(0, (a, b) => a + b);
                        final pct =
                            total > 0 ? e.value / total : 0.0;
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getActivityIcon(e.key),
                                    size: 18,
                                    color: _getActivityColor(e.key),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(e.key),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(e.value),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: _getActivityColor(
                                          e.key)
                                      .withOpacity(0.2),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                    _getActivityColor(e.key),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_activitySeconds.values
                              .every((v) => v == 0))
                        const Text(
                          'No activities recorded yet',
                          style: TextStyle(color: Colors.grey),
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

  Widget _buildStatCard(
      String label, String value, String unit, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(unit,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
