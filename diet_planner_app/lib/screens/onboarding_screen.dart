import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Form data
  final _nameController = TextEditingController();
  int _age = 25;
  double _weight = 70;
  double _height = 170;
  String _gender = 'male';
  String _activityLevel = 'moderate';
  String _goal = 'maintain';
  String _dietaryPreference = 'non_vegetarian';
  String _region = 'sri_lanka';

  @override
  void initState() {
    super.initState();
    // Pre-fill name from Firebase display name
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.user?.displayName != null) {
        _nameController.text = auth.user!.displayName!;
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 5) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveProfile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.user == null) return;

    final profile = UserProfile(
      uid: auth.user!.uid,
      name: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'User',
      age: _age,
      weightKg: _weight,
      heightCm: _height,
      gender: _gender,
      activityLevel: _activityLevel,
      goal: _goal,
      dietaryPreference: _dietaryPreference,
      region: _region,
    );

    await auth.saveProfile(profile);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: List.generate(6, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: index <= _currentPage
                            ? primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildNameAgePage(),
                  _buildBodyPage(),
                  _buildGenderActivityPage(),
                  _buildGoalPage(),
                  _buildDietaryPreferencePage(),
                  _buildRegionPage(),
                ],
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _currentPage == 5 ? _saveProfile : _nextPage,
                      child: Text(
                          _currentPage == 5 ? 'Get Started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameAgePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            "Let's get to know you",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We need some basic info to personalize your experience',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              prefixIcon: Icon(Icons.person_outlined),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Age: $_age years',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _age.toDouble(),
            min: 10,
            max: 80,
            divisions: 70,
            label: '$_age',
            onChanged: (value) {
              setState(() => _age = value.round());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBodyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Body Measurements',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'These are used to calculate your daily calorie needs',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          Text(
            'Weight: ${_weight.toStringAsFixed(1)} kg',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _weight,
            min: 30,
            max: 200,
            divisions: 340,
            label: '${_weight.toStringAsFixed(1)} kg',
            onChanged: (value) {
              setState(() => _weight = double.parse(value.toStringAsFixed(1)));
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Height: ${_height.toStringAsFixed(0)} cm',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _height,
            min: 100,
            max: 250,
            divisions: 150,
            label: '${_height.toStringAsFixed(0)} cm',
            onChanged: (value) {
              setState(() => _height = value.roundToDouble());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGenderActivityPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'About You',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 32),

          // Gender selection
          Text('Gender', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildOptionChip('Male', 'male', _gender,
                  (v) => setState(() => _gender = v), Icons.male),
              const SizedBox(width: 12),
              _buildOptionChip('Female', 'female', _gender,
                  (v) => setState(() => _gender = v), Icons.female),
            ],
          ),
          const SizedBox(height: 32),

          // Activity level
          Text('Activity Level',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...[
            ('Sedentary', 'sedentary', 'Little to no exercise'),
            ('Light', 'light', 'Exercise 1-3 days/week'),
            ('Moderate', 'moderate', 'Exercise 3-5 days/week'),
            ('Active', 'active', 'Hard exercise 6-7 days/week'),
            ('Very Active', 'very_active', 'Physical job + daily exercise'),
          ].map((item) => _buildActivityTile(item.$1, item.$2, item.$3)),
        ],
      ),
    );
  }

  Widget _buildGoalPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'What\'s your goal?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us adjust your daily calorie target',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          _buildGoalCard(
            'Lose Weight',
            'lose',
            Icons.trending_down,
            '-500 kcal/day (safe rate)',
            Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildGoalCard(
            'Maintain Weight',
            'maintain',
            Icons.balance,
            'Keep current weight',
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildGoalCard(
            'Gain Weight',
            'gain',
            Icons.trending_up,
            '+300 kcal/day (lean bulk)',
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildDietaryPreferencePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Dietary Preference',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us recommend the right foods for you',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          _buildDietaryCard(
            'Non-Vegetarian',
            'non_vegetarian',
            Icons.restaurant,
            'Includes all foods (meat, fish, eggs, vegetables)',
            Colors.deepOrange,
          ),
          const SizedBox(height: 12),
          _buildDietaryCard(
            'Vegetarian',
            'vegetarian',
            Icons.eco,
            'Plant-based foods, dairy, and eggs only',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildRegionPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Food Region',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll recommend foods popular in your region',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          _buildRegionCard(
            '🇱🇰  Sri Lanka',
            'sri_lanka',
            'Rice & curry, hoppers, dhal, kottu, and more',
            true,
          ),
          const SizedBox(height: 12),
          _buildRegionCard(
            '🇮🇳  India',
            'india',
            'Coming soon — biryani, roti, sambar, and more',
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildDietaryCard(String title, String value, IconData icon,
      String subtitle, Color color) {
    final selected = value == _dietaryPreference;
    return GestureDetector(
      onTap: () => setState(() => _dietaryPreference = value),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : null,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? color : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionCard(
      String title, String value, String subtitle, bool enabled) {
    final selected = value == _region;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _region = value) : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected && enabled
                ? primaryColor.withValues(alpha: 0.1)
                : null,
            border: Border.all(
              color: selected && enabled
                  ? primaryColor
                  : Colors.grey.shade300,
              width: selected && enabled ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? primaryColor : Colors.grey,
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Soon',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip(String label, String value, String groupValue,
      ValueChanged<String> onChanged, IconData icon) {
    final selected = value == groupValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : null,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                  size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityTile(String title, String value, String subtitle) {
    final selected = value == _activityLevel;
    return GestureDetector(
      onTap: () => setState(() => _activityLevel = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(String title, String value, IconData icon,
      String subtitle, Color color) {
    final selected = value == _goal;
    return GestureDetector(
      onTap: () => setState(() => _goal = value),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : null,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? color : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
