import 'package:flutter/material.dart';
import 'dart:ui' as dart_ui;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/tracking_service.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'dietary_screen.dart';
import 'activity_screen.dart';
import 'summary_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = const [
    DashboardScreen(),
    DietaryScreen(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Main content
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          // Bottom fading gradient
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 25,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.0),
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Floating Navigation Bar
          Positioned(
            bottom: 24,
            left: 40,
            right: 40,
            child: Container(
              decoration: BoxDecoration(
                color: isDark 
                    ? const Color(0xFF2F2F2F).withValues(alpha: 0.65)
                    : const Color(0xFFE3E5EB).withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 0),
                    blurStyle: BlurStyle.outer,
                  ),
                ],
                border:  Border.all(width: 0.9, color: isDark ? const Color(0xFF2F2F2F).withValues(alpha: 0.85) : const Color(0xFFE1E1EA).withValues(alpha: 0.9))
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                // Slight glass effect
                child: BackdropFilter(
                  filter: dart_ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 4.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(child: _buildNavItem(Icons.dashboard, 0, isDark)),
                        Expanded(child: _buildNavItem(Icons.restaurant_menu, 1, isDark)),
                        Expanded(child: _buildNavItem(Icons.directions_run, 2, isDark)),
                        Expanded(child: _buildNavItem(Icons.bar_chart, 3, isDark)),
                        Expanded(child: _buildNavItem(Icons.menu, 4, isDark)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index, bool isDark) {
    final isSelected = _currentIndex == index;
    final selectedBgColor = isDark ? const Color(0xFF4A4A4D) : const Color(0xFFC7C9D1);
    final unselectedColor = isDark ? Colors.white70 : Colors.black87;
    final selectedColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () {
        if (index == 4) {
          _showMenuBottomSheet(context, isDark);
        } else {
          setState(() {
            _currentIndex = index;
          });
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? selectedColor : unselectedColor,
              size: 25,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _showMenuBottomSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
          child: Container(
            decoration: BoxDecoration(
              color: isDark 
                  ? const Color(0xFF2F2F2F).withValues(alpha: 0.65)
                  : const Color(0xFFFFFFFF).withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 0),
                  blurStyle: BlurStyle.outer,
                ),
              ],
              border: Border.all(width: 0.4, color: isDark ? const Color(0xFF2F2F2F).withValues(alpha: 0.85) : const Color(0xFFE3E5EB).withValues(alpha: 0.85)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: dart_ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Profile'),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _currentIndex = 4;
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    isDark ? Divider(color: Colors.grey.withValues(alpha: 0.3), height: 1) : Divider(color: Colors.black.withValues(alpha: 0.3), height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Logout', style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        Navigator.pop(context);
                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        await authProvider.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
