"""Verify food scoring TFLite model outputs."""
import json, os, numpy as np

DATA_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\data"
MODEL_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\models"

with open(os.path.join(DATA_DIR, "foods_sri_lanka.json"), "r", encoding="utf-8") as f:
    foods = [f for f in json.load(f) if f["recommendable"]]

with open(os.path.join(MODEL_DIR, "food_scorer_metadata.json"), "r", encoding="utf-8") as f:
    meta = json.load(f)

import tensorflow as tf
interpreter = tf.lite.Interpreter(model_path=os.path.join(MODEL_DIR, "food_scorer.tflite"))
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

ns = meta["normalization"]
FOOD_GROUPS = meta["food_groups"]
MEAL_TYPES = meta["meal_types"]
GOALS = meta["goals"]

def encode(food, meal, goal):
    n = food["per_100g"]
    nutr = [
        (n["calories"] - ns["calories"]["mean"]) / ns["calories"]["std"],
        (n["protein"]  - ns["protein"]["mean"])  / ns["protein"]["std"],
        (n["fat"]      - ns["fat"]["mean"])      / ns["fat"]["std"],
        (n["carbs"]    - ns["carbs"]["mean"])     / ns["carbs"]["std"],
        (n["fiber"]    - ns["fiber"]["mean"])     / ns["fiber"]["std"],
    ]
    fg = [1.0 if food["food_group"] == g else 0.0 for g in FOOD_GROUPS]
    mt = [1.0 if meal == m else 0.0 for m in MEAL_TYPES]
    gl = [1.0 if goal == g else 0.0 for g in GOALS]
    return nutr + fg + mt + gl

def score(food, meal, goal):
    features = np.array([encode(food, meal, goal)], dtype=np.float32)
    interpreter.set_tensor(input_details[0]['index'], features)
    interpreter.invoke()
    return interpreter.get_tensor(output_details[0]['index'])[0][0]

lines = []
lines.append(f"Model size: {os.path.getsize(os.path.join(MODEL_DIR, 'food_scorer.tflite'))/1024:.1f} KB")
lines.append(f"Val MAE: {meta['val_mae']:.4f}")
lines.append(f"Training samples: {meta['training_samples']}")
lines.append("")

# Test meaningful scenarios
scenarios = [
    ("GOOD: Rice for lunch (maintain)", "cereals", "lunch", "maintain"),
    ("GOOD: Fish curry for dinner (lose)", "protein", "dinner", "lose"),
    ("GOOD: Dhal for lunch (maintain)", "legumes", "lunch", "maintain"),
    ("GOOD: Banana for snack (maintain)", "fruits", "snack", "maintain"),
    ("GOOD: Milk for breakfast (gain)", "dairy", "breakfast", "gain"),
    ("GOOD: Vegetables for dinner (lose)", "vegetables", "dinner", "lose"),
    ("BAD: Cake for dinner (lose)", "sweets", "dinner", "lose"),
    ("BAD: Oil for breakfast (lose)", "fats_oils", "breakfast", "lose"),
    ("NEUTRAL: Beverage for snack", "beverages", "snack", "maintain"),
]

lines.append("Scenario Predictions:")
for desc, group, meal, goal in scenarios:
    sample = next((f for f in foods if f["food_group"] == group), None)
    if sample:
        s = score(sample, meal, goal)
        lines.append(f"  {desc}: {s:.3f} ({sample['name'][:35]})")

# Top scored foods per meal type
for meal in MEAL_TYPES:
    scored = [(f, score(f, meal, "maintain")) for f in foods[:200]]
    scored.sort(key=lambda x: -x[1])
    lines.append(f"\nTop 5 for {meal} (maintain):")
    for f, s in scored[:5]:
        lines.append(f"  {s:.3f} - {f['name'][:40]} ({f['food_group']})")

out = "\n".join(lines)
with open(r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\verify_model_results.txt", "w") as f:
    f.write(out)
print(out)
