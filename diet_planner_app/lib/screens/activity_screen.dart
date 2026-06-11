import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getActivityIcon(String activity) {
    if (activity.contains('Walking')) return Icons.directions_walk;
    if (activity.contains('Jogging')) return Icons.directions_run;
    if (activity.contains('Stairs')) return Icons.stairs;
    if (activity.contains('Sitting') || activity.contains('Idle')) {
      return Icons.chair_alt;
    }
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
    final tracking = context.watch<TrackingProvider>();

    String durationText = "00:00:00";
    if (tracking.elapsedSeconds > 0) {
      final h = tracking.elapsedSeconds ~/ 3600;
      final m = (tracking.elapsedSeconds % 3600) ~/ 60;
      final s = tracking.elapsedSeconds % 60;
      durationText =
          "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Activity Tracker'),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Live Tracking',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (tracking.isTracking)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: tracking.isIdle ? 0.3 : _pulseController.value,
                        child: Icon(
                          Icons.circle,
                          color: tracking.isIdle
                              ? Colors.grey
                              : Colors.redAccent,
                          size: 16,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (tracking.isTracking) ...[
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: _getActivityColor(
                                tracking.currentActivity,
                              ).withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getActivityIcon(tracking.currentActivity),
                              size: 48,
                              color: _getActivityColor(
                                tracking.currentActivity,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tracking.currentActivity,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _getActivityColor(
                                tracking.currentActivity,
                              ),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getActivityColor(
                            tracking.currentActivity,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Model Confidence: ${(tracking.confidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: _getActivityColor(tracking.currentActivity),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        durationText,
                        style: Theme.of(context).textTheme.displaySmall
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
                        style: Theme.of(context).textTheme.headlineMedium
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

            if (tracking.isTracking || tracking.elapsedSeconds > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Duration',
                      Icons.timer,
                      durationText,
                      'hh:mm:ss',
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Calories',
                      Icons.local_fire_department,
                      tracking.totalCalories.toStringAsFixed(1),
                      'kcal',
                      Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tracking.activitySeconds.values.any(
                        (v) => v > 0,
                      )) ...[
                        Text(
                          'Activity Breakdown',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ...tracking.activitySeconds.entries
                            .where((e) => e.value > 0)
                            .map((e) {
                              final total = tracking.activitySeconds.values
                                  .fold(0, (a, b) => a + b);
                              final pct = total > 0 ? e.value / total : 0.0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct,
                                        minHeight: 6,
                                        backgroundColor: _getActivityColor(
                                          e.key,
                                        ).withValues(alpha: 0.2),
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
                      ],
                      if (tracking.activitySeconds.values.every((v) => v == 0))
                        const Text(
                          'No activities recorded yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    IconData icon,
    String value,
    String unit,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              unit,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
