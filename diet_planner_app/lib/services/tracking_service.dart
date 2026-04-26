import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

/// Initializes the background service but does NOT start it.
Future<void> initializeTrackingService() async {
  final service = FlutterBackgroundService();

  // Create a Low-Priority notification channel so it doesn't vibrate/ring constantly
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'diet_planner_tracker', // id
    'Activity Tracking', // title
    description: 'This channel is used for continuous activity tracking.',
    importance: Importance.low, 
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Don't start until user gives permissions!
      isForegroundMode: true,
      notificationChannelId: 'diet_planner_tracker',
      initialNotificationTitle: 'Diet Planner',
      initialNotificationContent: 'Initializing AI tracker...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location, AndroidForegroundType.specialUse],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ==========================================
  // STATE & BUFFERS
  // ==========================================
  List<List<double>> sensorBuffer = [];
  
  // Idle Mode Tracking Buffers
  List<double> xBuffer = [];
  List<double> yBuffer = [];
  List<double> zBuffer = [];
  bool isIdle = false;
  String currentActivity = "Waiting for data...";
  double userWeight = 70.0; // Overwritten by setWeight
  double confidence = 0.0;
  double currentSpeedMph = 0.0;

  // Persistence block
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String todayKey = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
  
  double totalCalories = prefs.getDouble('${todayKey}_calories') ?? 0.0; 
  int elapsedSeconds = prefs.getInt('${todayKey}_seconds') ?? 0;
  
  Map<String, int> activitySeconds = {
    'Walking': 0, 'Jogging': 0, 'Stairs': 0, 'Sitting': 0, 'Standing': 0
  };
  
  Map<String, double> activityCaloriesBurned = {
    'Walking': 0.0, 'Jogging': 0.0, 'Stairs': 0.0, 'Sitting': 0.0, 'Standing': 0.0
  };
  
  String mapString = prefs.getString('${todayKey}_durations') ?? "{}";
  if (mapString != "{}") {
    try {
      Map<String, dynamic> decoded = jsonDecode(mapString);
      decoded.forEach((key, value) {
        if (activitySeconds.containsKey(key)) {
           activitySeconds[key] = (value as num).toInt();
        }
      });
    } catch(e) {}
  }

  String calString = prefs.getString('${todayKey}_activity_cals') ?? "{}";
  if (calString != "{}") {
    try {
      Map<String, dynamic> decoded = jsonDecode(calString);
      decoded.forEach((key, value) {
        if (activityCaloriesBurned.containsKey(key)) {
           activityCaloriesBurned[key] = (value as num).toDouble();
        }
      });
    } catch(e) {}
  }

  // AI State
  Interpreter? interpreter;
  
  try {
    interpreter = await Interpreter.fromAsset('assets/models/har_phone_model.tflite');
    print("TFLite Model Loaded Successfully inside Isolate!");
  } catch (e) {
    print("Error loading TFLite model: $e");
  }

  // Listen to UI messages
  if (service is AndroidServiceInstance) {
    service.on('setWeight').listen((event) {
      if (event != null && event['weight'] != null) {
        userWeight = (event['weight'] as num).toDouble();
      }
    });
    
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  // ==========================================
  // 6-AXIS SENSOR FUSION (20Hz)
  // ==========================================
  double ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0;

  accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 50)).listen((event) {
    ax = event.x; ay = event.y; az = event.z;
    // Fast variance check for Idle Mode (300 frames = 15 seconds)
    xBuffer.add(ax);
    yBuffer.add(ay);
    zBuffer.add(az);
    if (zBuffer.length > 300) {
      xBuffer.removeAt(0);
      yBuffer.removeAt(0);
      zBuffer.removeAt(0);
      
      double meanX = xBuffer.reduce((a, b) => a + b) / xBuffer.length;
      double meanY = yBuffer.reduce((a, b) => a + b) / yBuffer.length;
      double meanZ = zBuffer.reduce((a, b) => a + b) / zBuffer.length;
      
      double varX = xBuffer.map((x) => pow(x - meanX, 2)).reduce((a, b) => a + b) / xBuffer.length;
      double varY = yBuffer.map((y) => pow(y - meanY, 2)).reduce((a, b) => a + b) / yBuffer.length;
      double varZ = zBuffer.map((z) => pow(z - meanZ, 2)).reduce((a, b) => a + b) / zBuffer.length;
      
      // Horizontal flat check: High gravity on Z axis (+/- 8.0), low gravity on X/Y axes
      bool isHorizontal = (meanZ.abs() > 8.0) && (meanX.abs() < 3.0) && (meanY.abs() < 3.0);
      
      // Human microum-scale vibration isolation (Table vs Pocket threshold based on self collected CSV dataset)
      bool mechanicallyStatic = varX < 0.005 && varY < 0.005 && varZ < 0.005;
      
      isIdle = mechanicallyStatic && isHorizontal;
    }
  });
  
  gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 50)).listen((event) {
    gx = event.x; gy = event.y; gz = event.z;
  });

  // Hard 50ms Sync Timer (20Hz)
  Timer.periodic(const Duration(milliseconds: 50), (timer) {
    if (isIdle) {
      sensorBuffer.clear(); // Drop buffer if stationary
      return; 
    }
    
    // Stack [ax, ay, az, gx, gy, gz]
    sensorBuffer.add([ax, ay, az, gx, gy, gz]);
    if (sensorBuffer.length > 200) {
      sensorBuffer.removeAt(0);
    }
  });

  // ==========================================
  // GPS GEOLOCATOR STREAM
  // ==========================================
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
    ),
  ).listen((Position position) {
    // Convert m/s to mph
    currentSpeedMph = position.speed * 2.23694;
  });

  // ==========================================
  // MET CALORIE ENGINE
  // ==========================================
  double getMetValue(String act, double speed) {
    // Phase 2 Dynamic Scaling Logic!
    if (act == "Walking") {
      if (speed <= 2.0) return 2.8;
      if (speed >= 4.0) return 5.0;
      return 2.8 + ((speed - 2.0) / 2.0) * (5.0 - 2.8);
    }
    if (act == "Jogging") {
      if (speed <= 4.0) return 6.0;
      if (speed >= 8.0) return 11.8;
      return 6.0 + ((speed - 4.0) / 4.0) * (11.8 - 6.0);
    }
    if (act == "Stairs") return 4.0;
    if (act == "Sitting") return 1.3;
    if (act == "Standing") return 1.8;
    return 1.3;
  }

  // ==========================================
  // INFERENCE & UI SYNC LOOP (1 Hz)
  // ==========================================
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (!isIdle) {
        elapsedSeconds++;
        
        // 1. Run inference every second if we have a full buffer (10 sec of data)
        if (sensorBuffer.length == 200 && interpreter != null) {
          var input = [sensorBuffer]; // Shape: [1, 200, 6]
          var output = List.filled(1 * 5, 0.0).reshape([1, 5]); // 5 activity classes
          
          interpreter.run(input, output);
          
          List<double> predictions = List<double>.from(output[0]);
          double maxScore = -1.0;
          int maxIndex = -1;
          for (int i = 0; i < predictions.length; i++) {
            if (predictions[i] > maxScore) {
              maxScore = predictions[i];
              maxIndex = i;
            }
          }
          
          List<String> classes = ["Walking", "Jogging", "Stairs", "Sitting", "Standing"];
          if (maxIndex != -1) {
             currentActivity = classes[maxIndex];
             confidence = maxScore;
          }
        }
        
        // 2. Real Math
        double liveMet = getMetValue(currentActivity, currentSpeedMph);
        double calsBurnedNow = (liveMet * userWeight) / 3600.0;
        totalCalories += calsBurnedNow; // Per second burn
        
        if (activitySeconds.containsKey(currentActivity)) {
           activitySeconds[currentActivity] = activitySeconds[currentActivity]! + 1;
           activityCaloriesBurned[currentActivity] = activityCaloriesBurned[currentActivity]! + calsBurnedNow;
        }
        
        // 3. Routine Caching (save state every 10 active seconds to avoid IO bottleneck)
        if (elapsedSeconds % 10 == 0) {
           prefs.setDouble('${todayKey}_calories', totalCalories);
           prefs.setInt('${todayKey}_seconds', elapsedSeconds);
           prefs.setString('${todayKey}_durations', jsonEncode(activitySeconds));
           prefs.setString('${todayKey}_activity_cals', jsonEncode(activityCaloriesBurned));
        }
    } else {
        currentActivity = "Idle (Sleeping)";
        confidence = 1.0;
    }

    // Update Android Notification
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        String msg = isIdle 
            ? "Battery Saver: Phone is idle on a surface." 
            : "Calories Burned: ${totalCalories.toStringAsFixed(1)} kcal | $currentActivity";
        
        flutterLocalNotificationsPlugin.show(
          id: 888,
          title: 'Diet Planner',
          body: msg,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'diet_planner_tracker',
              'Activity Tracking',
              icon: '@mipmap/ic_launcher',
              ongoing: true,
              importance: Importance.low, // Silent! No heads-up interruptions.
            ),
          ),
        );
      }
    }

    // Stream data back to the Flutter UI
    service.invoke('update', {
      'isTracking': true,
      'isIdle': isIdle,
      'elapsedSeconds': elapsedSeconds,
      'activity': currentActivity,
      'calories': totalCalories,
      'confidence': confidence,
      'activityDurations': activitySeconds, // Passing completely synched map!
      'activityCaloriesMap': activityCaloriesBurned, // Passing Dynamic GPS calculations!
    });
  });
}
