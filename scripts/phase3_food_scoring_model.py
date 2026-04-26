"""
Phase 3 — Step 2: Food Scoring Model
Trains a neural network that scores food suitability for a given meal context.
Converts to TFLite for on-device inference in Flutter.

Input features (24 total):
  - Nutritional (5): calories, protein, fat, carbs, fiber (normalized per 100g)
  - Food group (12): one-hot encoded
  - Meal type (4): one-hot (breakfast/lunch/dinner/snack)
  - User goal (3): one-hot (lose/maintain/gain)

Output: suitability score (0.0 - 1.0)
"""

import json
import numpy as np
import os

# ─────────────────────────────────────────────────────────
# 1. LOAD FOOD DATABASE
# ─────────────────────────────────────────────────────────
print("=" * 60)
print("Step 2: Food Scoring Model")
print("=" * 60)

DATA_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\data"
MODEL_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\models"
os.makedirs(MODEL_DIR, exist_ok=True)

with open(os.path.join(DATA_DIR, "foods_sri_lanka.json"), "r", encoding="utf-8") as f:
    foods = json.load(f)

# Filter to recommendable only
foods = [f for f in foods if f["recommendable"]]
print(f"\nLoaded {len(foods)} recommendable foods.")

# ─────────────────────────────────────────────────────────
# 2. DEFINE ENCODING SCHEMES
# ─────────────────────────────────────────────────────────
FOOD_GROUPS = [
    "cereals", "protein", "legumes", "vegetables", "fruits",
    "dairy", "fats_oils", "sweets", "beverages", "condiments",
    "snacks", "other"
]
MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack"]
GOALS = ["lose", "maintain", "gain"]

# Normalization stats (compute from data)
all_cals = [f["per_100g"]["calories"] for f in foods]
all_protein = [f["per_100g"]["protein"] for f in foods]
all_fat = [f["per_100g"]["fat"] for f in foods]
all_carbs = [f["per_100g"]["carbs"] for f in foods]
all_fiber = [f["per_100g"]["fiber"] for f in foods]

norm_stats = {
    "calories": {"mean": np.mean(all_cals), "std": max(np.std(all_cals), 1e-6)},
    "protein":  {"mean": np.mean(all_protein), "std": max(np.std(all_protein), 1e-6)},
    "fat":      {"mean": np.mean(all_fat), "std": max(np.std(all_fat), 1e-6)},
    "carbs":    {"mean": np.mean(all_carbs), "std": max(np.std(all_carbs), 1e-6)},
    "fiber":    {"mean": np.mean(all_fiber), "std": max(np.std(all_fiber), 1e-6)},
}

print(f"\nNormalization stats:")
for k, v in norm_stats.items():
    print(f"  {k}: mean={v['mean']:.2f}, std={v['std']:.2f}")


def encode_food(food, meal_type, goal):
    """Encode a single food item + context into a feature vector (24 dims)."""
    n = food["per_100g"]
    
    # Nutritional features (z-score normalized)
    nutr = [
        (n["calories"] - norm_stats["calories"]["mean"]) / norm_stats["calories"]["std"],
        (n["protein"]  - norm_stats["protein"]["mean"])  / norm_stats["protein"]["std"],
        (n["fat"]      - norm_stats["fat"]["mean"])      / norm_stats["fat"]["std"],
        (n["carbs"]    - norm_stats["carbs"]["mean"])     / norm_stats["carbs"]["std"],
        (n["fiber"]    - norm_stats["fiber"]["mean"])     / norm_stats["fiber"]["std"],
    ]
    
    # Food group one-hot
    fg = [1.0 if food["food_group"] == g else 0.0 for g in FOOD_GROUPS]
    
    # Meal type one-hot
    mt = [1.0 if meal_type == m else 0.0 for m in MEAL_TYPES]
    
    # Goal one-hot
    gl = [1.0 if goal == g else 0.0 for g in GOALS]
    
    return nutr + fg + mt + gl


# ─────────────────────────────────────────────────────────
# 3. GENERATE TRAINING DATA
# ─────────────────────────────────────────────────────────
print("\nGenerating training data...")

# Goal-specific macro preferences (protein fraction targets)
GOAL_PROTEIN_MIN = {"lose": 0.25, "maintain": 0.15, "gain": 0.20}
GOAL_FAT_MAX = {"lose": 0.30, "maintain": 0.35, "gain": 0.35}

# Goal-aware calorie distribution per meal
GOAL_MEAL_CALS = {
    # (min_cal, max_cal) per 100g for the food to be "good" in this meal context
    "lose": {"breakfast": (50, 300), "lunch": (50, 350), "dinner": (30, 250), "snack": (20, 150)},
    "maintain": {"breakfast": (50, 400), "lunch": (50, 450), "dinner": (50, 400), "snack": (20, 200)},
    "gain": {"breakfast": (100, 500), "lunch": (100, 500), "dinner": (100, 500), "snack": (50, 300)},
}

X_train = []
y_train = []
rng = np.random.RandomState(42)

for goal in GOALS:
    for meal_type in MEAL_TYPES:
        cal_range = GOAL_MEAL_CALS[goal][meal_type]
        protein_min = GOAL_PROTEIN_MIN[goal]
        fat_max = GOAL_FAT_MAX[goal]
        
        for food in foods:
            n = food["per_100g"]
            cal = n["calories"]
            prot = n["protein"]
            fat = n["fat"]
            carbs = n["carbs"]
            
            # Calculate macro ratios (avoid div by zero)
            total_macro_g = prot + fat + carbs
            if total_macro_g < 1:
                prot_ratio = 0
                fat_ratio = 0
            else:
                prot_ratio = (prot * 4) / max(cal, 1)   # protein cal fraction
                fat_ratio = (fat * 9) / max(cal, 1)      # fat cal fraction
            
            features = encode_food(food, meal_type, goal)
            
            # Compute suitability score (0-1) based on multiple factors
            score = 0.0
            
            # Factor 1: Does this food match the meal type? (0.0 or 0.3)
            if meal_type in food.get("meal_types", []):
                score += 0.3
            
            # Factor 2: Is the calorie density appropriate? (0.0 to 0.25)
            if cal_range[0] <= cal <= cal_range[1]:
                score += 0.25
            elif cal > cal_range[1]:
                # Slightly penalize but don't zero out
                overshoot = (cal - cal_range[1]) / cal_range[1]
                score += max(0, 0.25 - overshoot * 0.15)
            
            # Factor 3: Protein adequacy (0.0 to 0.2)
            if prot_ratio >= protein_min:
                score += 0.2
            else:
                score += 0.2 * (prot_ratio / max(protein_min, 0.01))
            
            # Factor 4: Fat moderation (0.0 to 0.15)
            if fat_ratio <= fat_max:
                score += 0.15
            else:
                overshoot = (fat_ratio - fat_max) / max(fat_max, 0.01)
                score += max(0, 0.15 - overshoot * 0.1)
            
            # Factor 5: Food group diversity bonus (0.0 to 0.1)
            # Prefer core nutritious groups over sweets/beverages/other
            good_groups = {"cereals", "protein", "legumes", "vegetables", "fruits", "dairy"}
            if food["food_group"] in good_groups:
                score += 0.1
            elif food["food_group"] in {"fats_oils", "condiments"}:
                score += 0.05  # useful as accompaniment
            
            score = min(1.0, max(0.0, score))
            
            X_train.append(features)
            y_train.append(score)

X_train = np.array(X_train, dtype=np.float32)
y_train = np.array(y_train, dtype=np.float32)

print(f"  Training samples: {len(X_train)}")
print(f"  Feature dimensions: {X_train.shape[1]}")
print(f"  Score distribution: min={y_train.min():.3f}, max={y_train.max():.3f}, "
      f"mean={y_train.mean():.3f}, std={y_train.std():.3f}")

# Shuffle
idx = rng.permutation(len(X_train))
X_train = X_train[idx]
y_train = y_train[idx]

# Split 90/10 for train/val
split = int(0.9 * len(X_train))
X_val = X_train[split:]
y_val = y_train[split:]
X_train_split = X_train[:split]
y_train_split = y_train[:split]


# ─────────────────────────────────────────────────────────
# 4. BUILD AND TRAIN NEURAL NETWORK
# ─────────────────────────────────────────────────────────
print("\nTraining neural network...")

try:
    import tensorflow as tf
    print(f"  TensorFlow version: {tf.__version__}")
except ImportError:
    print("  ERROR: TensorFlow not installed. Installing...")
    import subprocess
    subprocess.check_call(["pip", "install", "tensorflow"])
    import tensorflow as tf

model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(24,)),
    tf.keras.layers.Dense(32, activation='relu'),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(16, activation='relu'),
    tf.keras.layers.Dropout(0.1),
    tf.keras.layers.Dense(1, activation='sigmoid'),
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
    loss='mse',
    metrics=['mae'],
)

model.summary()

# Train
history = model.fit(
    X_train_split, y_train_split,
    validation_data=(X_val, y_val),
    epochs=50,
    batch_size=64,
    verbose=1,
)

# Evaluate
val_loss, val_mae = model.evaluate(X_val, y_val, verbose=0)
print(f"\n  Validation Loss: {val_loss:.4f}")
print(f"  Validation MAE:  {val_mae:.4f}")


# ─────────────────────────────────────────────────────────
# 5. CONVERT TO TFLITE
# ─────────────────────────────────────────────────────────
print("\nConverting to TFLite...")

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]
tflite_model = converter.convert()

tflite_path = os.path.join(MODEL_DIR, "food_scorer.tflite")
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)

tflite_size = os.path.getsize(tflite_path)
print(f"  ✅ food_scorer.tflite saved ({tflite_size / 1024:.1f} KB)")


# ─────────────────────────────────────────────────────────
# 6. VERIFY TFLITE MODEL
# ─────────────────────────────────────────────────────────
print("\nVerifying TFLite model...")

interpreter = tf.lite.Interpreter(model_path=tflite_path)
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print(f"  Input shape:  {input_details[0]['shape']}")
print(f"  Input dtype:  {input_details[0]['dtype']}")
print(f"  Output shape: {output_details[0]['shape']}")
print(f"  Output dtype: {output_details[0]['dtype']}")

# Test with a few sample foods
test_cases = [
    ("Rice (lunch, lose)", "cereals", "lunch", "lose"),
    ("Rice (breakfast, lose)", "cereals", "breakfast", "lose"),
    ("Fish (dinner, gain)", "protein", "dinner", "gain"),
    ("Cake (snack, lose)", "sweets", "snack", "lose"),
    ("Dhal (lunch, maintain)", "legumes", "lunch", "maintain"),
]

print("\n  Sample predictions:")
for desc, target_group, meal, goal in test_cases:
    # Find a food in this group
    sample = next((f for f in foods if f["food_group"] == target_group), None)
    if sample:
        features = np.array([encode_food(sample, meal, goal)], dtype=np.float32)
        interpreter.set_tensor(input_details[0]['index'], features)
        interpreter.invoke()
        score = interpreter.get_tensor(output_details[0]['index'])[0][0]
        print(f"    {desc} ({sample['name'][:30]}): {score:.3f}")


# ─────────────────────────────────────────────────────────
# 7. SAVE MODEL METADATA
# ─────────────────────────────────────────────────────────
print("\nSaving model metadata...")

metadata = {
    "model_name": "food_scorer",
    "version": "1.0",
    "input_features": 24,
    "feature_order": [
        "calories_zscore", "protein_zscore", "fat_zscore", "carbs_zscore", "fiber_zscore",
        *[f"group_{g}" for g in FOOD_GROUPS],
        *[f"meal_{m}" for m in MEAL_TYPES],
        *[f"goal_{g}" for g in GOALS],
    ],
    "food_groups": FOOD_GROUPS,
    "meal_types": MEAL_TYPES,
    "goals": GOALS,
    "normalization": {
        k: {"mean": float(v["mean"]), "std": float(v["std"])}
        for k, v in norm_stats.items()
    },
    "training_samples": len(X_train),
    "val_mae": float(val_mae),
}

meta_path = os.path.join(MODEL_DIR, "food_scorer_metadata.json")
with open(meta_path, "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=2)

print(f"  ✅ food_scorer_metadata.json saved")

print("\n" + "=" * 60)
print("DONE! Food scoring model trained and converted to TFLite.")
print("=" * 60)
