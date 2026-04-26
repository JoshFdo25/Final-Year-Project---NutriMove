import json, os
d = r'C:\Users\joshw\OneDrive\Desktop\FYP_Work\diet_planner_app\assets\data'
out = r'C:\Users\joshw\OneDrive\Desktop\FYP_Work\verify_results.txt'

lines = []
for f in ['foods_sri_lanka.json', 'recipes_sri_lanka.json', 'portions.json']:
    path = os.path.join(d, f)
    if os.path.exists(path):
        size = os.path.getsize(path)
        with open(path, 'r', encoding='utf-8') as fp:
            data = json.load(fp)
        if isinstance(data, list):
            lines.append(f'{f}: {size/1024:.1f} KB, {len(data)} items')
        elif isinstance(data, dict):
            lines.append(f'{f}: {size/1024:.1f} KB, {len(data)} keys')
    else:
        lines.append(f'{f}: NOT FOUND')

with open(os.path.join(d, 'foods_sri_lanka.json'), 'r', encoding='utf-8') as fp:
    foods = json.load(fp)

rec = sum(1 for f in foods if f['recommendable'])
non_rec = sum(1 for f in foods if not f['recommendable'])
veg = sum(1 for f in foods if 'vegetarian' in f['dietary_tags'])
nveg = sum(1 for f in foods if 'non_vegetarian' in f['dietary_tags'])
lines.append(f'\nTotal: {len(foods)}, Recommendable: {rec}, Non-rec: {non_rec}')
lines.append(f'Vegetarian: {veg}, Non-veg: {nveg}')

groups = {}
for f in foods:
    g = f['food_group']
    groups[g] = groups.get(g, 0) + 1
lines.append('\nFood Groups:')
for g, c in sorted(groups.items(), key=lambda x: -x[1]):
    lines.append(f'  {g}: {c}')

lines.append('\nSample Foods:')
for f in foods[:8]:
    lines.append(f'  {f["name"]}: {f["per_100g"]["calories"]} kcal | group={f["food_group"]} | tags={f["dietary_tags"]} | meals={f["meal_types"]} | rec={f["recommendable"]}')

lines.append('\nAlcohol items (non-recommendable):')
for f in foods:
    if not f['recommendable']:
        lines.append(f'  {f["name"]}')

with open(out, 'w', encoding='utf-8') as fp:
    fp.write('\n'.join(lines))

print('Results written to verify_results.txt')
