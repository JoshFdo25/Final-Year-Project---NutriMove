/// User profile model for the Diet Planner app.
/// Stores physical data needed for BMR and calorie calculations.
library;

class UserProfile {
  final String uid; // Firebase Auth UID
  final String name;
  final int age;
  final double weightKg;
  final double heightCm;
  final String gender; // 'male' or 'female'
  final String activityLevel; // 'sedentary', 'light', 'moderate', 'active', 'very_active'
  final String goal; // 'lose', 'maintain', 'gain'
  final String dietaryPreference; // 'vegetarian' or 'non_vegetarian'
  final String region; // 'sri_lanka' (extensible to 'india', etc.)

  UserProfile({
    required this.uid,
    required this.name,
    required this.age,
    required this.weightKg,
    required this.heightCm,
    required this.gender,
    this.activityLevel = 'moderate',
    this.goal = 'maintain',
    this.dietaryPreference = 'non_vegetarian',
    this.region = 'sri_lanka',
  });

  /// Create from Firestore document
  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    return UserProfile(
      uid: uid,
      name: map['name'] ?? '',
      age: (map['age'] ?? 25).toInt(),
      weightKg: (map['weightKg'] ?? 70).toDouble(),
      heightCm: (map['heightCm'] ?? 170).toDouble(),
      gender: map['gender'] ?? 'male',
      activityLevel: map['activityLevel'] ?? 'moderate',
      goal: map['goal'] ?? 'maintain',
      dietaryPreference: map['dietaryPreference'] ?? 'non_vegetarian',
      region: map['region'] ?? 'sri_lanka',
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'age': age,
      'weightKg': weightKg,
      'heightCm': heightCm,
      'gender': gender,
      'activityLevel': activityLevel,
      'goal': goal,
      'dietaryPreference': dietaryPreference,
      'region': region,
    };
  }

  /// Create a copy with updated fields
  UserProfile copyWith({
    String? uid,
    String? name,
    int? age,
    double? weightKg,
    double? heightCm,
    String? gender,
    String? activityLevel,
    String? goal,
    String? dietaryPreference,
    String? region,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      age: age ?? this.age,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      gender: gender ?? this.gender,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      region: region ?? this.region,
    );
  }

  @override
  String toString() =>
      'UserProfile(name: $name, age: $age, weight: ${weightKg}kg, '
      'height: ${heightCm}cm, gender: $gender, goal: $goal)';
}
