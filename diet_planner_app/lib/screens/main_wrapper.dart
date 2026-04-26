import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/tracking_service.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'activity_screen.dart';
import 'summary_screen.dart';
import 'profile_screen.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = const [
    DashboardScreen(),
    ActivityScreen(),
    SummaryScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _startTrackingAuto();
  }

  Future<void> _startTrackingAuto() async {
    // 1. Android 10+ Foreground Location FIRST
    PermissionStatus locWhenInUse = await Permission.locationWhenInUse.request();
    if (locWhenInUse.isGranted) {
      // 2. Android 10+ Background Location (Only succeeds natively if WhenInUse is granted first)
      await Permission.locationAlways.request();
    }
    // 3. Android Sensors
    await Permission.sensors.request();
    await Permission.activityRecognition.request();
    // 4. Android Battery Optimization Ignore
    await Permission.ignoreBatteryOptimizations.request();
    // 5. Notifications
    await Permission.notification.request();

    final service = FlutterBackgroundService();

    // Grab profile configuration
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userWeight = authProvider.userProfile?.weightKg ?? 70.0;
    
    // ALWAYS configure the service on boot so the UI rebuilds the EventChannels
    await initializeTrackingService();
    
    if (await service.isRunning()) {
        service.invoke('setWeight', {'weight': userWeight});
        return;
    }

    // Start if it isn't running yet
    await service.startService();
    
    // Inject the personal payload to the background isolate mapping our algorithm bounds
    service.invoke('setWeight', {'weight': userWeight});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Summary'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
