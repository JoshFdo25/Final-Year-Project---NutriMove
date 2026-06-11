import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class TrackingProvider extends ChangeNotifier {
  bool _isTracking = false;
  bool _isIdle = false;
  int _elapsedSeconds = 0;
  String _currentActivity = 'Unknown';
  double _totalCalories = 0.0;
  double _confidence = 0.0;

  Map<String, int> _activitySeconds = {};
  Map<String, double> _activityCalories = {};

  StreamSubscription<Map<String, dynamic>?>? _serviceListener;

  TrackingProvider() {
    _initListener();
  }

  void _initListener() async {
    final service = FlutterBackgroundService();
    
    // Fast initial check
    _isTracking = await service.isRunning();
    notifyListeners();

    _serviceListener = service.on('update').listen((event) {
      if (event != null) {
        _isTracking = event['isTracking'] ?? false;
        _isIdle = event['isIdle'] ?? false;
        _elapsedSeconds = event['elapsedSeconds'] ?? 0;
        _currentActivity = event['activity'] ?? 'Unknown';
        _totalCalories = (event['calories'] ?? 0.0).toDouble();
        _confidence = (event['confidence'] ?? 0.0).toDouble();

        if (event['activityDurations'] != null) {
          Map<dynamic, dynamic> d = event['activityDurations'];
          _activitySeconds = d.map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          );
        }

        if (event['activityCaloriesMap'] != null) {
          Map<dynamic, dynamic> c = event['activityCaloriesMap'];
          _activityCalories = c.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          );
        }

        // Notify UI to rebuild mapped widgets
        notifyListeners();
      }
    });
  }

  // --- Getters ---
  bool get isTracking => _isTracking;
  bool get isIdle => _isIdle;
  int get elapsedSeconds => _elapsedSeconds;
  String get currentActivity => _currentActivity;
  double get totalCalories => _totalCalories;
  double get confidence => _confidence;

  Map<String, int> get activitySeconds => _activitySeconds;
  
  /// Helper to get activity durations in hours format
  Map<String, double> get activityDurationsHours => 
      _activitySeconds.map((k, v) => MapEntry(k, v / 3600.0));

  /// Helper to get activity durations in minutes format
  Map<String, double> get activityDurationsMinutes => 
      _activitySeconds.map((k, v) => MapEntry(k, v / 60.0));

  Map<String, double> get activityCalories => _activityCalories;

  @override
  void dispose() {
    _serviceListener?.cancel();
    super.dispose();
  }
}
