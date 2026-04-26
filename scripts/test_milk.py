import json

with open("c:/Users/joshw/OneDrive/Desktop/FYP_Work/diet_planner_app/assets/data/foods_sri_lanka.json", encoding="utf-8") as f:
    data = json.load(f)

for item in data:
    if "MILK" in item['name'].upper():
        print(f"{item['name']} - {item.get('food_group', '')}")
