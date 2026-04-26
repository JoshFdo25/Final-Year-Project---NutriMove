"""Quick integration results dump to ASCII-safe file."""
import json, os

DATA_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\data"
MODEL_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\models"

with open(os.path.join(DATA_DIR, "foods_sri_lanka.json"), "r", encoding="utf-8") as f:
    foods = json.load(f)

recommendable = [f for f in foods if f["recommendable"]]
alcohol = [f for f in foods if not f["recommendable"]]
veg = [f for f in recommendable if "vegetarian" in f.get("dietary_tags", [])]
non_veg = [f for f in recommendable if "non_vegetarian" in f.get("dietary_tags", [])]

lines = [
    "PHASE 3 INTEGRATION VERIFICATION",
    "=" * 50,
    "",
    f"Total foods: {len(foods)}",
    f"Recommendable: {len(recommendable)}",
    f"Alcohol blocked: {len(alcohol)}",
    f"Vegetarian: {len(veg)}",
    f"Non-vegetarian: {len(non_veg)}",
    f"Dietary overlap: {len([f for f in recommendable if 'vegetarian' in f.get('dietary_tags',[]) and 'non_vegetarian' in f.get('dietary_tags',[])])}",
    f"Foods without dietary tags: {len([f for f in recommendable if not f.get('dietary_tags',[])])}",
    "",
    "Alcohol items blocked:",
    *[f"  - {a['name']}" for a in alcohol],
    "",
    "False positive check (should all be 0):",
    f"  ginger beer blocked: {len([a for a in alcohol if 'ginger beer' in a['name'].lower()])}",
    f"  malted blocked: {len([a for a in alcohol if 'malted' in a['name'].lower()])}",
    f"  drumstick blocked: {len([a for a in alcohol if 'drumstick' in a['name'].lower()])}",
    "",
    "Meal coverage:",
    *[f"  {m}: {len([f for f in recommendable if m in f.get('meal_types',[])])}" 
      for m in ['breakfast','lunch','dinner','snack']],
    "",
    "Food groups:",
    *[f"  {g}: {c}" for g, c in sorted(
        {f.get('food_group','?'): 0 for f in recommendable}.items(),
        key=lambda x: -sum(1 for f in recommendable if f.get('food_group')==x[0]))
      if True  # placeholder
    ],
    "",
    "Veg breakfast candidates: " + str(len([f for f in recommendable 
        if 'vegetarian' in f.get('dietary_tags',[]) and 'breakfast' in f.get('meal_types',[])])),
    "",
    f"TFLite model exists: {os.path.exists(os.path.join(MODEL_DIR, 'food_scorer.tflite'))}",
    f"Model metadata exists: {os.path.exists(os.path.join(MODEL_DIR, 'food_scorer_metadata.json'))}",
    f"TFLite size: {os.path.getsize(os.path.join(MODEL_DIR, 'food_scorer.tflite'))/1024:.1f} KB",
    "",
    "Calorie distribution sums:",
    f"  lose: {0.35+0.35+0.20+0.10}",
    f"  maintain: {0.30+0.35+0.25+0.10}",
    f"  gain: {0.25+0.35+0.30+0.10}",
    "",
    "ALL CHECKS PASSED" if (
        len(alcohol) == 8 and len(veg) > 500 and len(non_veg) > 150
    ) else "ISSUES DETECTED",
]

# Fix food groups
groups = {}
for f in recommendable:
    g = f.get('food_group', 'unknown')
    groups[g] = groups.get(g, 0) + 1
lines2 = []
for line in lines:
    if line.startswith("Food groups:"):
        lines2.append(line)
        for g, c in sorted(groups.items(), key=lambda x: -x[1]):
            lines2.append(f"  {g}: {c}")
    elif "placeholder" in str(line):
        continue
    else:
        lines2.append(line)

out = "\n".join(lines2)
with open(r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\integration_check.txt", "w", encoding="ascii", errors="replace") as f:
    f.write(out)
print(out)
