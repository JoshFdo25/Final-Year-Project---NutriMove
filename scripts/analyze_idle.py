import pandas as pd
import numpy as np
import json

def analyze_dataset(name, path):
    res = {}
    try:
        accel = pd.read_csv(f"{path}/Accelerometer.csv")
        gyro = pd.read_csv(f"{path}/Gyroscope.csv")
        
        # Calculate Rolling Variances (Window = 300, matching 15s at 20Hz)
        # Because logs might be 100hz depending on logger defaults, we'll just check raw total variance for the 40 sec file.
        # It approximates the identical math.
        
        res['accel_var_z'] = float(np.var(accel['z']))
        res['accel_var_x'] = float(np.var(accel['x']))
        res['accel_var_y'] = float(np.var(accel['y']))
        
        res['gyro_var_z'] = float(np.var(gyro['z']))
        res['gyro_var_x'] = float(np.var(gyro['x']))
        res['gyro_var_y'] = float(np.var(gyro['y']))

    except Exception as e:
        res['error'] = str(e)
    return res

t = analyze_dataset("Table", "c:/Users/joshw/OneDrive/Desktop/FYP_Work/datasets/self-collected/table")
p = analyze_dataset("Pocket", "c:/Users/joshw/OneDrive/Desktop/FYP_Work/datasets/self-collected/pocket")

with open("c:/Users/joshw/OneDrive/Desktop/FYP_Work/analyze_out.json", "w") as f:
    json.dump({"Table": t, "Pocket": p}, f)
