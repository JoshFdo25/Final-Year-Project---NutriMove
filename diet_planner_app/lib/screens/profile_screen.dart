import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/energy_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  late int _age;
  late double _weight;
  late double _height;
  late String _gender;
  late String _activityLevel;
  late String _goal;
  late String _dietaryPreference;
  late String _region;
  bool _editing = false;
  List<String> _blockedFoods = [];

  @override
  void initState() {
    super.initState();
    final profile =
        Provider.of<AuthProvider>(context, listen: false).userProfile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _age = profile?.age ?? 25;
    _weight = profile?.weightKg ?? 70;
    _height = profile?.heightCm ?? 170;
    _gender = profile?.gender ?? 'male';
    _activityLevel = profile?.activityLevel ?? 'moderate';
    _goal = profile?.goal ?? 'maintain';
    _dietaryPreference = profile?.dietaryPreference ?? 'non_vegetarian';
    _region = profile?.region ?? 'sri_lanka';
    _loadBlockedFoods();
  }

  Future<void> _loadBlockedFoods() async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList('blocked_foods') ?? [];
    setState(() => _blockedFoods = blocked);
  }

  Future<void> _unblockFood(String foodName) async {
    final prefs = await SharedPreferences.getInstance();
    _blockedFoods.remove(foodName);
    await prefs.setStringList('blocked_foods', _blockedFoods);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$foodName" unblocked')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.updateProfile({
      'name': _nameController.text.trim(),
      'age': _age,
      'weightKg': _weight,
      'heightCm': _height,
      'gender': _gender,
      'activityLevel': _activityLevel,
      'goal': _goal,
      'dietaryPreference': _dietaryPreference,
      'region': _region,
    });
    setState(() => _editing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.userProfile;
    final bmr = profile != null ? EnergyService.calculateBmr(profile) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveChanges,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User avatar & name
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor:
                          Theme.of(context).colorScheme.primary,
                      child: Text(
                        (profile?.name ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_editing)
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                isDense: true,
                              ),
                            )
                          else
                            Text(
                              profile?.name ?? 'User',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            authProvider.user?.email ?? '',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Body stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Body Stats',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_editing) ...[
                      Text('Age: $_age years'),
                      Slider(
                        value: _age.toDouble(),
                        min: 10,
                        max: 80,
                        divisions: 70,
                        label: '$_age',
                        onChanged: (v) =>
                            setState(() => _age = v.round()),
                      ),
                      Text(
                          'Weight: ${_weight.toStringAsFixed(1)} kg'),
                      Slider(
                        value: _weight,
                        min: 30,
                        max: 200,
                        divisions: 340,
                        label: '${_weight.toStringAsFixed(1)} kg',
                        onChanged: (v) => setState(() =>
                            _weight = double.parse(
                                v.toStringAsFixed(1))),
                      ),
                      Text(
                          'Height: ${_height.toStringAsFixed(0)} cm'),
                      Slider(
                        value: _height,
                        min: 100,
                        max: 250,
                        divisions: 150,
                        label: '${_height.toStringAsFixed(0)} cm',
                        onChanged: (v) => setState(
                            () => _height = v.roundToDouble()),
                      ),
                    ] else ...[
                      _buildStatRow(context, 'Age',
                          '${profile?.age ?? 0} years', Icons.cake),
                      _buildStatRow(
                          context,
                          'Weight',
                          '${profile?.weightKg.toStringAsFixed(1) ?? 0} kg',
                          Icons.monitor_weight),
                      _buildStatRow(
                          context,
                          'Height',
                          '${profile?.heightCm.toStringAsFixed(0) ?? 0} cm',
                          Icons.height),
                      _buildStatRow(
                          context,
                          'Gender',
                          profile?.gender.capitalize() ?? '',
                          Icons.person),
                      _buildStatRow(context, 'BMR',
                          '${bmr.toStringAsFixed(0)} kcal/day', Icons.whatshot),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Goal
            if (_editing)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Goal',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'lose', label: Text('Lose')),
                          ButtonSegment(
                              value: 'maintain',
                              label: Text('Maintain')),
                          ButtonSegment(
                              value: 'gain', label: Text('Gain')),
                        ],
                        selected: {_goal},
                        onSelectionChanged: (value) =>
                            setState(() => _goal = value.first),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Theme toggle
            Card(
              child: ListTile(
                leading: Icon(
                  themeProvider.isDarkMode
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
                title: const Text('Dark Mode'),
                subtitle: Text(
                  themeProvider.isDarkMode ? 'On' : 'Off',
                ),
                trailing: Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (_) => themeProvider.toggleTheme(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Dietary Preference & Region
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diet Preferences',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_editing) ...[
                      Text('Dietary Type',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'non_vegetarian',
                            label: Text('Non-Veg'),
                            icon: Icon(Icons.restaurant),
                          ),
                          ButtonSegment(
                            value: 'vegetarian',
                            label: Text('Vegetarian'),
                            icon: Icon(Icons.eco),
                          ),
                        ],
                        selected: {_dietaryPreference},
                        onSelectionChanged: (value) =>
                            setState(() => _dietaryPreference = value.first),
                      ),
                    ] else ...[
                      _buildStatRow(
                        context,
                        'Diet',
                        _dietaryPreference == 'vegetarian'
                            ? 'Vegetarian'
                            : 'Non-Vegetarian',
                        _dietaryPreference == 'vegetarian'
                            ? Icons.eco
                            : Icons.restaurant,
                      ),
                      _buildStatRow(
                        context,
                        'Region',
                        _region == 'sri_lanka'
                            ? '\u{1F1F1}\u{1F1F0} Sri Lanka'
                            : _region,
                        Icons.public,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Logout
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await authProvider.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Blocked Foods
            if (_blockedFoods.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.block,
                              size: 20,
                              color: Colors.red.shade400),
                          const SizedBox(width: 8),
                          Text(
                            'Blocked Foods',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${_blockedFoods.length} items',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to unblock and allow in recommendations',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ...(_blockedFoods.map((food) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.no_food,
                                color: Colors.red.shade300, size: 20),
                            title: Text(food, style: const TextStyle(fontSize: 14)),
                            trailing: TextButton(
                              onPressed: () => _unblockFood(food),
                              child: const Text('Unblock',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
      BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
