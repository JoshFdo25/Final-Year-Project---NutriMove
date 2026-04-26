"""
============================================================================
Phase 1.5b: Phone Fusion TFLite Conversion (Fallback Model)
============================================================================
Converts the phone-only fusion model to TFLite for when watch is unavailable.
Uses same approach as Phase 1.5 (knowledge distillation).

Run: py -3.12 phase1_5b_phone_fusion_tflite_updated.py
============================================================================
"""

import os
import numpy as np
import pandas as pd
import joblib
import json
from pathlib import Path
from tqdm import tqdm
import xgboost as xgb
import lightgbm as lgb

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR = Path(r"c:\Users\joshw\OneDrive\Desktop\FYP_Work")
MODELS_DIR = BASE_DIR / "Models"
DATASETS_DIR = BASE_DIR / "Datasets" / "wisdm-dataset" / "raw"
MODEL_TO_CONVERT = "har_fusion_phone"
OUTPUT_DIR = MODELS_DIR / "tflite"
OUTPUT_DIR.mkdir(exist_ok=True)

ACTIVITY_LABELS = {
    'A': 'Walking', 'B': 'Jogging', 'C': 'Stairs',
    'D': 'Sitting', 'E': 'Standing'
}

WINDOW_SIZE = 200
OVERLAP = 0.5

print("=" * 70)
print("Phase 1.5b: Phone Fusion TFLite Conversion (Fallback)")
print("=" * 70)

# ============================================================================
# STEP 1: Load Saved Model
# ============================================================================

print("\n📦 Step 1: Loading phone fusion model...")

model_dir = MODELS_DIR / MODEL_TO_CONVERT
sklearn_model = joblib.load(model_dir / "model.joblib")
scaler = joblib.load(model_dir / "scaler.joblib")
label_encoder = joblib.load(model_dir / "label_encoder.joblib")
feature_names = joblib.load(model_dir / "feature_names.joblib")
training_config = joblib.load(model_dir / "training_config.joblib")

PRIMARY_ACTIVITIES = list(label_encoder.classes_)

print(f"   Model type: {type(sklearn_model).__name__}")
print(f"   Number of features: {len(feature_names)}")
print(f"   Classes: {[ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_]}")
print(f"   Config: {training_config}")

# ============================================================================
# STEP 2: Load Phone Sensor Data
# ============================================================================

print("\n📊 Step 2: Loading phone sensor data...")


def load_sensor_data(sensor_dir, sensor_name):
    all_data = []
    files = sorted(sensor_dir.glob("*.txt"))
    for f in tqdm(files, desc=f"Loading {sensor_name}"):
        try:
            with open(f, 'r') as file:
                lines = file.readlines()
            rows = []
            for line in lines:
                line = line.strip().rstrip(';').rstrip(',')
                if not line:
                    continue
                parts = line.split(',')
                if len(parts) >= 6:
                    try:
                        rows.append({
                            'subject': int(parts[0]),
                            'activity': parts[1].strip(),
                            'timestamp': int(parts[2]),
                            'x': float(parts[3]),
                            'y': float(parts[4]),
                            'z': float(parts[5])
                        })
                    except (ValueError, IndexError):
                        continue
            if rows:
                all_data.append(pd.DataFrame(rows))
        except Exception as e:
            print(f"   Warning: Could not load {f.name}: {e}")
    if all_data:
        return pd.concat(all_data, ignore_index=True)
    return pd.DataFrame()


def extract_window_features(window_data, prefix=""):
    features = {}
    for axis in ['x', 'y', 'z']:
        data = window_data[axis].values
        p = f"{prefix}{axis}_" if prefix else f"{axis}_"

        features[f'{p}mean'] = np.mean(data)
        features[f'{p}std'] = np.std(data)
        features[f'{p}min'] = np.min(data)
        features[f'{p}max'] = np.max(data)
        features[f'{p}range'] = np.max(data) - np.min(data)
        features[f'{p}median'] = np.median(data)
        features[f'{p}mad'] = np.median(np.abs(data - np.median(data)))
        features[f'{p}iqr'] = np.percentile(data, 75) - np.percentile(data, 25)
        features[f'{p}skew'] = pd.Series(data).skew()
        features[f'{p}kurtosis'] = pd.Series(data).kurtosis()
        features[f'{p}rms'] = np.sqrt(np.mean(data ** 2))
        features[f'{p}energy'] = np.sum(data ** 2) / len(data)
        features[f'{p}zero_crossings'] = np.sum(np.diff(np.sign(data)) != 0)

        if len(data) > 1:
            fft_vals = np.abs(np.fft.rfft(data))
            features[f'{p}fft_mean'] = np.mean(fft_vals)
            features[f'{p}fft_std'] = np.std(fft_vals)
            features[f'{p}fft_max'] = np.max(fft_vals)
            features[f'{p}fft_energy'] = np.sum(fft_vals ** 2) / len(fft_vals)

            freqs = np.fft.rfftfreq(len(data), d=1/20)
            if np.sum(fft_vals) > 0:
                features[f'{p}dominant_freq'] = freqs[np.argmax(fft_vals[1:]) + 1] if len(fft_vals) > 1 else 0
            else:
                features[f'{p}dominant_freq'] = 0

    if prefix:
        p = prefix
    else:
        p = ""

    x_data = window_data['x'].values
    y_data = window_data['y'].values
    z_data = window_data['z'].values

    features[f'{p}magnitude_mean'] = np.mean(np.sqrt(x_data**2 + y_data**2 + z_data**2))
    features[f'{p}magnitude_std'] = np.std(np.sqrt(x_data**2 + y_data**2 + z_data**2))

    if len(x_data) > 1:
        features[f'{p}xy_corr'] = np.corrcoef(x_data, y_data)[0, 1] if np.std(x_data) > 0 and np.std(y_data) > 0 else 0
        features[f'{p}xz_corr'] = np.corrcoef(x_data, z_data)[0, 1] if np.std(x_data) > 0 and np.std(z_data) > 0 else 0
        features[f'{p}yz_corr'] = np.corrcoef(y_data, z_data)[0, 1] if np.std(y_data) > 0 and np.std(z_data) > 0 else 0
    else:
        features[f'{p}xy_corr'] = 0
        features[f'{p}xz_corr'] = 0
        features[f'{p}yz_corr'] = 0

    return features


# Load only phone sensors
sensors_needed = ['phone_accel', 'phone_gyro']
prefix_map = {
    'phone_accel': 'phone_accel_',
    'phone_gyro': 'phone_gyro_',
}

sensor_dirs = {
    'phone_accel': DATASETS_DIR / "phone" / "accel",
    'phone_gyro': DATASETS_DIR / "phone" / "gyro",
}

sensor_data = {}
for sensor in sensors_needed:
    print(f"\n   Loading {sensor}...")
    sensor_data[sensor] = load_sensor_data(sensor_dirs[sensor], sensor)
    sensor_data[sensor] = sensor_data[sensor][
        sensor_data[sensor]['activity'].isin(PRIMARY_ACTIVITIES)
    ].reset_index(drop=True)
    print(f"   {sensor}: {len(sensor_data[sensor]):,} samples")

# ============================================================================
# STEP 3: Extract Features
# ============================================================================

print("\n🔧 Step 3: Extracting features...")

common_subjects = None
for sensor in sensors_needed:
    subjects = set(sensor_data[sensor]['subject'].unique())
    common_subjects = subjects if common_subjects is None else common_subjects & subjects

print(f"   Common subjects: {len(common_subjects)}")

all_feature_rows = []
all_raw_windows = []
all_labels = []
all_subjects = []
step = int(WINDOW_SIZE * (1 - OVERLAP))

for subject in tqdm(sorted(common_subjects), desc="Processing subjects"):
    for activity in PRIMARY_ACTIVITIES:
        sensor_activity_data = {}
        min_len = float('inf')

        for sensor in sensors_needed:
            data = sensor_data[sensor][
                (sensor_data[sensor]['subject'] == subject) &
                (sensor_data[sensor]['activity'] == activity)
            ].reset_index(drop=True)
            sensor_activity_data[sensor] = data
            if len(data) < min_len:
                min_len = len(data)

        if min_len < WINDOW_SIZE:
            continue

        for start in range(0, min_len - WINDOW_SIZE + 1, step):
            combined_features = {}
            raw_accel = sensor_activity_data['phone_accel'].iloc[start:start + WINDOW_SIZE][['x', 'y', 'z']].values
            raw_gyro = sensor_activity_data['phone_gyro'].iloc[start:start + WINDOW_SIZE][['x', 'y', 'z']].values
            raw_combined = np.concatenate((raw_accel, raw_gyro), axis=1) # Shape: (200, 6)

            for sensor in sensors_needed:
                window = sensor_activity_data[sensor].iloc[start:start + WINDOW_SIZE]
                feats = extract_window_features(window, prefix=prefix_map[sensor])
                combined_features.update(feats)
            all_feature_rows.append(combined_features)
            all_raw_windows.append(raw_combined)
            all_labels.append(activity)
            all_subjects.append(subject)

X_df = pd.DataFrame(all_feature_rows)
X_raw = np.array(all_raw_windows, dtype=np.float32)
y_list = all_labels
subjects_arr = np.array(all_subjects)

print(f"   Total windows: {len(X_df):,}")
print(f"   Features per window: {X_df.shape[1]}")

# Align features
saved_feature_set = set(feature_names)
current_feature_set = set(X_df.columns)
missing = saved_feature_set - current_feature_set
extra = current_feature_set - saved_feature_set

if missing:
    print(f"   ⚠️ Missing features (adding zeros): {len(missing)}")
    missing_df = pd.DataFrame(0, index=X_df.index, columns=list(missing))
    X_df = pd.concat([X_df, missing_df], axis=1)
if extra:
    print(f"   ℹ️ Extra features (removing): {len(extra)}")

X_df = X_df[feature_names]
X = X_df.values.astype(np.float32)
y = np.array(y_list)
y_encoded = label_encoder.transform(y)
num_classes = len(label_encoder.classes_)
X_scaled = scaler.transform(X).astype(np.float32)

print(f"   Final shape: X={X.shape}, X_raw={X_raw.shape}, y={y_encoded.shape}")

# ============================================================================
# STEP 4: Validate sklearn model & Split Data (Subject-Wise)
# ============================================================================

print("\n📊 Step 4: Subject-Wise splitting & Validating scikit-learn teacher...")

from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import classification_report, accuracy_score, f1_score

gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
train_idx, test_idx = next(gss.split(X_scaled, y_encoded, groups=subjects_arr))

print(f"   Train subjects: {len(np.unique(subjects_arr[train_idx]))}")
print(f"   Test subjects: {len(np.unique(subjects_arr[test_idx]))}")

X_train_static, X_test_static = X_scaled[train_idx], X_scaled[test_idx]
X_train_raw, X_test_raw = X_raw[train_idx], X_raw[test_idx]
y_train, y_test = y_encoded[train_idx], y_encoded[test_idx]

sklearn_preds = sklearn_model.predict(X_test_static)
sklearn_acc = accuracy_score(y_test, sklearn_preds)
sklearn_f1 = f1_score(y_test, sklearn_preds, average='weighted')

print(f"   Accuracy: {sklearn_acc:.4f}")
print(f"   F1-Score: {sklearn_f1:.4f}")
print(classification_report(
    y_test, sklearn_preds,
    target_names=[ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_]
))

# ============================================================================
# STEP 5: Train Keras Neural Network
# ============================================================================

print("\n🧠 Step 5: Training Keras neural network...")

import tensorflow as tf
from tensorflow import keras

y_train_onehot = keras.utils.to_categorical(y_train, num_classes)
y_test_onehot = keras.utils.to_categorical(y_test, num_classes)

model = keras.Sequential([
    keras.layers.Input(shape=(WINDOW_SIZE, 6)),
    keras.layers.Conv1D(filters=64, kernel_size=3, activation='relu'),
    keras.layers.BatchNormalization(),
    keras.layers.MaxPooling1D(pool_size=2),
    keras.layers.Conv1D(filters=128, kernel_size=3, activation='relu'),
    keras.layers.BatchNormalization(),
    keras.layers.MaxPooling1D(pool_size=2),
    keras.layers.GlobalAveragePooling1D(),
    keras.layers.Dropout(0.3),
    keras.layers.Dense(64, activation='relu'),
    keras.layers.Dense(num_classes, activation='softmax')
])

model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

model.summary()

# Knowledge distillation
print("\n   Training with knowledge distillation (Feature Distillation)...")
sklearn_train_probs = sklearn_model.predict_proba(X_train_static).astype(np.float32)

model.fit(
    X_train_raw, sklearn_train_probs,
    validation_data=(X_test_raw, y_test_onehot),
    epochs=30, batch_size=64, verbose=1,
    callbacks=[
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=3),
    ]
)

# Fine-tune
print("\n   Fine-tuning with true labels...")
model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.0005),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

model.fit(
    X_train_raw, y_train_onehot,
    validation_data=(X_test_raw, y_test_onehot),
    epochs=30, batch_size=64, verbose=1,
    callbacks=[
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=3),
    ]
)

keras_preds = np.argmax(model.predict(X_test_raw), axis=1)
keras_acc = accuracy_score(y_test, keras_preds)
keras_f1 = f1_score(y_test, keras_preds, average='weighted')

print(f"\n   Keras Accuracy: {keras_acc:.4f}")
print(f"   Keras F1-Score: {keras_f1:.4f}")

# Save Keras model
keras_path = OUTPUT_DIR / "har_phone_keras_model.keras"
model.save(str(keras_path))

# ============================================================================
# STEP 6: Convert to TFLite
# ============================================================================

print("\n📱 Step 6: Converting to TFLite...")

# Float32
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

tflite_path = OUTPUT_DIR / "har_phone_model.tflite"
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)

tflite_size = os.path.getsize(tflite_path) / 1024
print(f"   ✅ Float32: {tflite_path} ({tflite_size:.1f} KB)")

# Float16 quantized
converter_quant = tf.lite.TFLiteConverter.from_keras_model(model)
converter_quant.optimizations = [tf.lite.Optimize.DEFAULT]

def representative_dataset():
    for i in range(min(500, len(X_train_raw))):
        yield [X_train_raw[i:i+1]]

converter_quant.representative_dataset = representative_dataset
converter_quant.target_spec.supported_types = [tf.float16]

tflite_quant_model = converter_quant.convert()

tflite_quant_path = OUTPUT_DIR / "har_phone_model_quantized.tflite"
with open(tflite_quant_path, 'wb') as f:
    f.write(tflite_quant_model)

tflite_quant_size = os.path.getsize(tflite_quant_path) / 1024
print(f"   ✅ Quantized: {tflite_quant_path} ({tflite_quant_size:.1f} KB)")

# ============================================================================
# STEP 7: Validate TFLite
# ============================================================================

print("\n✅ Step 7: Validating TFLite model...")

def run_tflite_inference(tflite_path, X_data):
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    predictions = []
    for i in range(len(X_data)):
        input_data = X_data[i:i+1].astype(np.float32)
        interpreter.set_tensor(input_details[0]['index'], input_data)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]['index'])
        predictions.append(np.argmax(output))
    return np.array(predictions)

tflite_preds = run_tflite_inference(tflite_path, X_test_raw)
tflite_acc = accuracy_score(y_test, tflite_preds)
tflite_f1 = f1_score(y_test, tflite_preds, average='weighted')

tflite_quant_preds = run_tflite_inference(tflite_quant_path, X_test_raw)
tflite_quant_acc = accuracy_score(y_test, tflite_quant_preds)
tflite_quant_f1 = f1_score(y_test, tflite_quant_preds, average='weighted')

# ============================================================================
# STEP 8: Summary
# ============================================================================

print("\n" + "=" * 70)
print("📊 PHONE FUSION MODEL — FINAL COMPARISON")
print("=" * 70)

results = pd.DataFrame({
    'Model': ['Scikit-Learn', 'Keras', 'TFLite Float32', 'TFLite Quantized'],
    'Accuracy': [sklearn_acc, keras_acc, tflite_acc, tflite_quant_acc],
    'F1-Score': [sklearn_f1, keras_f1, tflite_f1, tflite_quant_f1],
    'Size': [
        f"{os.path.getsize(model_dir / 'model.joblib') / 1024:.1f} KB",
        f"{os.path.getsize(keras_path) / 1024:.1f} KB",
        f"{tflite_size:.1f} KB",
        f"{tflite_quant_size:.1f} KB"
    ],
})
print(results.to_string(index=False))

# Save metadata
metadata = {
    'model_name': MODEL_TO_CONVERT,
    'model_type': 'phone_fallback_1d_cnn',
    'num_features': 6,
    'feature_names': ['accel_x', 'accel_y', 'accel_z', 'gyro_x', 'gyro_y', 'gyro_z'],
    'num_classes': num_classes,
    'class_labels': list(label_encoder.classes_),
    'class_names': [ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_],
    'sensors_required': ['phone_accel', 'phone_gyro'],
    'window_size': WINDOW_SIZE,
    'sampling_rate_hz': 20,
    'overlap': OVERLAP,
    'scaler_mean': [],
    'scaler_scale': [],
    'sklearn_accuracy': float(sklearn_acc),
    'keras_accuracy': float(keras_acc),
    'tflite_accuracy': float(tflite_acc),
    'tflite_quant_accuracy': float(tflite_quant_acc),
}

metadata_path = OUTPUT_DIR / "phone_model_metadata.json"
with open(metadata_path, 'w') as f:
    json.dump(metadata, f, indent=2)

print(f"\n   ✅ Metadata saved: {metadata_path}")

print("\n" + "=" * 70)
print("🎉 Phone Fusion Fallback Model Complete!")
print("=" * 70)
print(f"\n   📁 All TFLite models in: {OUTPUT_DIR}")
print(f"\n   🔗 Full Fusion (watch connected):")
print(f"      har_model.tflite / har_model_quantized.tflite")
print(f"\n   📱 Phone Fallback (no watch):")
print(f"      har_phone_model.tflite / har_phone_model_quantized.tflite")
print(f"\n   Flutter logic:")
print(f"      if (watch connected) → use har_model.tflite (232 features)")
print(f"      else → use har_phone_model.tflite (116 features)")
