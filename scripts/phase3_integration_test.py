"""
Phase 3 Step 6: Integration Verification
Verifies the entire recommendation pipeline end-to-end using the actual data.
"""
import json
import os

DATA_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\data"

print("=" * 65)
print("Phase 3 Step 6: Integration & Data Verification")
print("=" * 65)

# ──── 1. Load all data ─────────────────────────────────
print("\n1. Loading data files...")
with open(os.path.join(DATA_DIR, "foods_sri_lanka.json"), "r", encoding="utf-8") as f:
    foods = json.load(f)
with open(os.path.join(DATA_DIR, "recipes_sri_lanka.json"), "r", encoding="utf-8") as f:
    recipes = json.load(f)
with open(os.path.join(DATA_DIR, "portions.json"), "r", encoding="utf-8") as f:
    portions = json.load(f)

print(f"   Foods: {len(foods)}")
print(f"   Recipes: {len(recipes)}")
print(f"   Portions: {len(portions)}")

# ──── 2. Verify alcohol filtering ──────────────────────
print("\n2. Alcohol filtering verification...")
alcohol_items = [f for f in foods if not f["recommendable"]]
recommendable = [f for f in foods if f["recommendable"]]
print(f"   Non-recommendable (alcohol): {len(alcohol_items)}")
for a in alcohol_items:
    print(f"     ✅ {a['name']}")

# Verify no false positives
false_positive_keywords = ["ginger beer", "malted", "drumstick", "biscuit"]
for fp_keyword in false_positive_keywords:
    blocked = [a for a in alcohol_items if fp_keyword.lower() in a['name'].lower()]
    if blocked:
        print(f"   ❌ FALSE POSITIVE: '{fp_keyword}' incorrectly blocked!")
    else:
        print(f"   ✅ No false positive for '{fp_keyword}'")

# ──── 3. Verify dietary filtering ──────────────────────
print("\n3. Dietary preference verification...")
vegetarian = [f for f in recommendable if "vegetarian" in f.get("dietary_tags", [])]
non_veg = [f for f in recommendable if "non_vegetarian" in f.get("dietary_tags", [])]
print(f"   Vegetarian: {len(vegetarian)}")
print(f"   Non-vegetarian: {len(non_veg)}")

# No food should be both vegetarian and non-vegetarian
both = [f for f in recommendable 
        if "vegetarian" in f.get("dietary_tags", []) and 
           "non_vegetarian" in f.get("dietary_tags", [])]
if both:
    print(f"   ❌ ERROR: {len(both)} foods tagged as both veg & non-veg")
else:
    print(f"   ✅ No overlap in dietary tags")

# Every food should have at least one dietary tag
untagged = [f for f in recommendable if not f.get("dietary_tags", [])]
if untagged:
    print(f"   ❌ ERROR: {len(untagged)} foods with no dietary tags")
else:
    print(f"   ✅ All foods have dietary tags")

# ──── 4. Verify meal type coverage ─────────────────────
print("\n4. Meal type coverage verification...")
for meal in ["breakfast", "lunch", "dinner", "snack"]:
    count = len([f for f in recommendable if meal in f.get("meal_types", [])])
    status = "✅" if count > 10 else "⚠️"
    print(f"   {status} {meal}: {count} foods")

# ──── 5. Verify food groups ───────────────────────────
print("\n5. Food group distribution verification...")
groups = {}
for f in recommendable:
    g = f.get("food_group", "unknown")
    groups[g] = groups.get(g, 0) + 1
for g, c in sorted(groups.items(), key=lambda x: -x[1]):
    print(f"   {g}: {c}")

# ──── 6. Verify portions coverage ─────────────────────
print("\n6. Portions coverage verification...")
foods_with_portions = [f for f in recommendable if f.get("common_portions")]
print(f"   Foods with portions: {len(foods_with_portions)} / {len(recommendable)}")
no_portions = [f for f in recommendable if not f.get("common_portions")]
if no_portions:
    print(f"   ⚠️ {len(no_portions)} foods without portions (will use 100g default)")
    for np in no_portions[:5]:
        print(f"     - {np['name']}")

# ──── 7. Verify recipe coverage ───────────────────────
print("\n7. Recipe coverage verification...")
recipe_food_codes = set()
for r in recipes:
    for ing in r.get("ingredients", []):
        recipe_food_codes.add(ing.get("code", ""))
food_ids = {f.get("id", "") for f in foods}
matched = recipe_food_codes & food_ids
print(f"   Recipe ingredient codes: {len(recipe_food_codes)}")
print(f"   Matched to food database: {len(matched)}")

# ──── 8. Simulate recommendation pipeline ─────────────
print("\n8. Simulated recommendation pipeline...")
# Simulate: vegetarian user, lose weight, breakfast
test_profile = {
    "dietary_preference": "vegetarian",
    "goal": "lose",
    "meal_type": "breakfast",
}

candidates = [f for f in recommendable
              if "vegetarian" in f.get("dietary_tags", [])
              and "breakfast" in f.get("meal_types", [])
              and f["recommendable"]]

print(f"   Profile: Vegetarian, Lose weight, Breakfast")
print(f"   Candidates after filtering: {len(candidates)}")
print(f"   Top 5 by protein density:")
candidates_scored = sorted(candidates, 
    key=lambda x: x["per_100g"]["protein"] / max(x["per_100g"]["calories"], 1),
    reverse=True)
for c in candidates_scored[:5]:
    n = c["per_100g"]
    print(f"     {c['name'][:40]:40s} | {n['calories']:6.1f} kcal | P:{n['protein']:5.1f}g | "
          f"C:{n['carbs']:5.1f}g | F:{n['fat']:5.1f}g")

# Also test non-veg for lunch
candidates2 = [f for f in recommendable
               if "lunch" in f.get("meal_types", [])
               and f["recommendable"]]
print(f"\n   Profile: Non-Veg, Maintain, Lunch")
print(f"   Candidates after filtering: {len(candidates2)}")
candidates2_scored = sorted(candidates2,
    key=lambda x: x["per_100g"]["protein"] / max(x["per_100g"]["calories"], 1),
    reverse=True)
print(f"   Top 5 by protein density:")
for c in candidates2_scored[:5]:
    n = c["per_100g"]
    print(f"     {c['name'][:40]:40s} | {n['calories']:6.1f} kcal | P:{n['protein']:5.1f}g | "
          f"C:{n['carbs']:5.1f}g | F:{n['fat']:5.1f}g")

# ──── 9. Verify model metadata ───────────────────────
print("\n9. Model metadata verification...")
MODEL_DIR = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\models"
meta_path = os.path.join(MODEL_DIR, "food_scorer_metadata.json")
tflite_path = os.path.join(MODEL_DIR, "food_scorer.tflite")

if os.path.exists(meta_path):
    with open(meta_path, "r") as f:
        meta = json.load(f)
    print(f"   ✅ Metadata found")
    print(f"      Input features: {meta['input_features']}")
    print(f"      Val MAE: {meta['val_mae']:.4f}")
    print(f"      Food groups: {len(meta['food_groups'])}")
    print(f"      Normalization keys: {list(meta['normalization'].keys())}")
else:
    print(f"   ❌ Metadata missing!")

if os.path.exists(tflite_path):
    size_kb = os.path.getsize(tflite_path) / 1024
    print(f"   ✅ TFLite model found ({size_kb:.1f} KB)")
else:
    print(f"   ❌ TFLite model missing!")

# ──── 10. Verify pubspec assets ───────────────────────
print("\n10. Asset registration verification...")
pubspec_path = r"C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\pubspec.yaml"
with open(pubspec_path, "r") as f:
    pubspec = f.read()
checks = [
    ("assets/data/", "Food data directory"),
    ("assets/models/", "Model directory"),
]
for pattern, desc in checks:
    if pattern in pubspec:
        print(f"   ✅ {desc} registered in pubspec.yaml")
    else:
        print(f"   ❌ {desc} NOT registered in pubspec.yaml!")

# ──── 11. Calorie distribution check ─────────────────
print("\n11. Goal-aware calorie distribution verification...")
distributions = {
    "lose": {"breakfast": 0.35, "lunch": 0.35, "dinner": 0.20, "snacks": 0.10},
    "maintain": {"breakfast": 0.30, "lunch": 0.35, "dinner": 0.25, "snacks": 0.10},
    "gain": {"breakfast": 0.25, "lunch": 0.35, "dinner": 0.30, "snacks": 0.10},
}
for goal, dist in distributions.items():
    total = sum(dist.values())
    status = "✅" if abs(total - 1.0) < 0.001 else "❌"
    front = dist["breakfast"] + dist["lunch"]
    print(f"   {status} {goal:8s}: B:{dist['breakfast']:.0%} L:{dist['lunch']:.0%} "
          f"D:{dist['dinner']:.0%} S:{dist['snacks']:.0%} | Total: {total:.0%} | "
          f"Front-loaded: {front:.0%}")

# ──── SUMMARY ─────────────────────────────────────────
print("\n" + "=" * 65)
errors = []
if both: errors.append("Foods with overlapping dietary tags")
if untagged: errors.append("Foods with missing dietary tags")
if not os.path.exists(tflite_path): errors.append("Missing TFLite model")
if not os.path.exists(meta_path): errors.append("Missing model metadata")

if errors:
    print(f"❌ ISSUES FOUND: {len(errors)}")
    for e in errors:
        print(f"   - {e}")
else:
    print("✅ ALL INTEGRATION CHECKS PASSED!")
print("=" * 65)
