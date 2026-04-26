"""
============================================================================
Phase 1.5: TFLite Model Conversion for Mobile Deployment
============================================================================

This script converts the best scikit-learn HAR model to TensorFlow Lite format
for on-device inference in the Flutter mobile app.

Approach:
  1. Load the saved scikit-learn model, scaler, and feature names
  2. Load the original WISDM data and recreate the training features
  3. Train a TensorFlow/Keras neural network to match the sklearn model
  4. Convert the Keras model to TFLite with quantization
  5. Validate converted model accuracy

Run from: c:\\Users\\joshw\\OneDrive\\Desktop\\FYP_Work\\
============================================================================
"""

import os
import sys
import numpy as np
import pandas as pd
import joblib
from pathlib import Path
from tqdm import tqdm

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR = Path(r"c:\Users\joshw\OneDrive\Desktop\FYP_Work")
MODELS_DIR = BASE_DIR / "Models"
DATASETS_DIR = BASE_DIR / "Datasets" / "wisdm-dataset" / "raw"

# Which model to convert - use the best performing one
# Options: 'har_watch_gyro', 'har_fusion_full', 'har_fusion_watch', etc.
MODEL_TO_CONVERT = "har_fusion_full"  # Best overall F1-score

OUTPUT_DIR = MODELS_DIR / "tflite"
OUTPUT_DIR.mkdir(exist_ok=True)

# WISDM activity labels
ACTIVITY_LABELS = {
    'A': 'Walking', 'B': 'Jogging', 'C': 'Stairs',
    'D': 'Sitting', 'E': 'Standing', 'F': 'Typing',
    'G': 'Brushing Teeth', 'H': 'Eating Soup', 'I': 'Eating Chips',
    'J': 'Eating Pasta', 'K': 'Drinking', 'L': 'Eating Sandwich',
    'M': 'Kicking', 'O': 'Playing Catch', 'P': 'Dribbling',
    'Q': 'Writing', 'R': 'Clapping', 'S': 'Folding Clothes'
}

# Will be set dynamically from saved model's classes
PRIMARY_ACTIVITIES = None  # Set after loading model

WINDOW_SIZE = 200  # 10 seconds at 20Hz
OVERLAP = 0.5

print("=" * 70)
print("Phase 1.5: TFLite Model Conversion")
print("=" * 70)

# ============================================================================
# STEP 1: Load the Saved Scikit-Learn Model
# ============================================================================

print("\n📦 Step 1: Loading saved scikit-learn model...")

model_dir = MODELS_DIR / MODEL_TO_CONVERT
sklearn_model = joblib.load(model_dir / "model.joblib")
scaler = joblib.load(model_dir / "scaler.joblib")
label_encoder = joblib.load(model_dir / "label_encoder.joblib")
feature_names = joblib.load(model_dir / "feature_names.joblib")
training_config = joblib.load(model_dir / "training_config.joblib")

# Set PRIMARY_ACTIVITIES from the model's actual trained classes
PRIMARY_ACTIVITIES = list(label_encoder.classes_)

print(f"   Model type: {type(sklearn_model).__name__}")
print(f"   Number of features: {len(feature_names)}")
print(f"   Classes: {list(label_encoder.classes_)}")
print(f"   Class labels: {[ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_]}")
print(f"   Training config: {training_config}")
print(f"   Activities to use: {PRIMARY_ACTIVITIES}")

# ============================================================================
# STEP 2: Load WISDM Data and Recreate Features
# ============================================================================

print("\n📊 Step 2: Loading WISDM data and recreating features...")


def load_sensor_data(sensor_dir, sensor_name):
    """Load all subject files from a sensor directory."""
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
    """Extract time and frequency domain features from a sensor window."""
    features = {}
    
    for axis in ['x', 'y', 'z']:
        data = window_data[axis].values
        p = f"{prefix}{axis}_" if prefix else f"{axis}_"
        
        # Time-domain features
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
        
        # Frequency-domain features
        if len(data) > 1:
            fft_vals = np.abs(np.fft.rfft(data))
            features[f'{p}fft_mean'] = np.mean(fft_vals)
            features[f'{p}fft_std'] = np.std(fft_vals)
            features[f'{p}fft_max'] = np.max(fft_vals)
            features[f'{p}fft_energy'] = np.sum(fft_vals ** 2) / len(fft_vals)
            
            freqs = np.fft.rfftfreq(len(data), d=1/20)  # 20Hz sampling
            if np.sum(fft_vals) > 0:
                features[f'{p}dominant_freq'] = freqs[np.argmax(fft_vals[1:]) + 1] if len(fft_vals) > 1 else 0
            else:
                features[f'{p}dominant_freq'] = 0
    
    # Cross-axis features
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


def create_windowed_features(df, window_size=200, overlap=0.5, prefix=""):
    """Create sliding windows and extract features."""
    step = int(window_size * (1 - overlap))
    all_features = []
    all_labels = []
    
    for subject in df['subject'].unique():
        subject_data = df[df['subject'] == subject]
        
        for activity in subject_data['activity'].unique():
            activity_data = subject_data[subject_data['activity'] == activity].reset_index(drop=True)
            
            for start in range(0, len(activity_data) - window_size + 1, step):
                window = activity_data.iloc[start:start + window_size]
                features = extract_window_features(window, prefix=prefix)
                all_features.append(features)
                all_labels.append(activity)
    
    return pd.DataFrame(all_features), all_labels


# Determine which sensors to load based on model
if MODEL_TO_CONVERT == "har_fusion_full":
    sensors_needed = ['phone_accel', 'phone_gyro', 'watch_accel', 'watch_gyro']
elif MODEL_TO_CONVERT == "har_fusion_watch":
    sensors_needed = ['watch_accel', 'watch_gyro']
elif MODEL_TO_CONVERT == "har_fusion_phone":
    sensors_needed = ['phone_accel', 'phone_gyro']
elif MODEL_TO_CONVERT == "har_phone_accel":
    sensors_needed = ['phone_accel']
elif MODEL_TO_CONVERT == "har_phone_gyro":
    sensors_needed = ['phone_gyro']
elif MODEL_TO_CONVERT == "har_watch_accel":
    sensors_needed = ['watch_accel']
elif MODEL_TO_CONVERT == "har_watch_gyro":
    sensors_needed = ['watch_gyro']
else:
    sensors_needed = ['watch_gyro']  # Default

sensor_dirs = {
    'phone_accel': DATASETS_DIR / "phone" / "accel",
    'phone_gyro': DATASETS_DIR / "phone" / "gyro",
    'watch_accel': DATASETS_DIR / "watch" / "accel",
    'watch_gyro': DATASETS_DIR / "watch" / "gyro",
}

# Load sensor data
sensor_data = {}
for sensor in sensors_needed:
    print(f"\n   Loading {sensor}...")
    sensor_data[sensor] = load_sensor_data(sensor_dirs[sensor], sensor)
    
    # Filter to primary activities
    sensor_data[sensor] = sensor_data[sensor][
        sensor_data[sensor]['activity'].isin(PRIMARY_ACTIVITIES)
    ].reset_index(drop=True)
    
    print(f"   {sensor}: {len(sensor_data[sensor]):,} samples")

# ============================================================================
# STEP 3: Create Features (matching Phase 1/1b exactly)
# ============================================================================

print("\n🔧 Step 3: Extracting features (matching original pipeline)...")

if len(sensors_needed) == 1:
    # Single sensor model
    sensor_name = sensors_needed[0]
    X_df, y_list = create_windowed_features(
        sensor_data[sensor_name],
        window_size=WINDOW_SIZE,
        overlap=OVERLAP,
        prefix=""
    )
else:
    # Fusion model - need to align windows across sensors
    # For fusion models, we extract features per sensor with prefixes, then merge
    
    prefix_map = {
        'phone_accel': 'phone_accel_',
        'phone_gyro': 'phone_gyro_',
        'watch_accel': 'watch_accel_',
        'watch_gyro': 'watch_gyro_',
    }
    
    # Find common subjects across all sensors
    common_subjects = None
    for sensor in sensors_needed:
        subjects = set(sensor_data[sensor]['subject'].unique())
        common_subjects = subjects if common_subjects is None else common_subjects & subjects
    
    print(f"   Common subjects across sensors: {len(common_subjects)}")
    
    all_feature_rows = []
    all_labels = []
    step = int(WINDOW_SIZE * (1 - OVERLAP))
    
    for subject in tqdm(sorted(common_subjects), desc="Processing subjects"):
        for activity in PRIMARY_ACTIVITIES:
            # Get data per sensor for this subject + activity
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
            
            # Create aligned windows
            for start in range(0, min_len - WINDOW_SIZE + 1, step):
                combined_features = {}
                
                for sensor in sensors_needed:
                    window = sensor_activity_data[sensor].iloc[start:start + WINDOW_SIZE]
                    feats = extract_window_features(window, prefix=prefix_map[sensor])
                    combined_features.update(feats)
                
                all_feature_rows.append(combined_features)
                all_labels.append(activity)
    
    X_df = pd.DataFrame(all_feature_rows)
    y_list = all_labels

print(f"   Total windows: {len(X_df):,}")
print(f"   Features per window: {X_df.shape[1]}")

# Align feature columns with saved model
# The saved model may have different feature ordering
saved_feature_set = set(feature_names)
current_feature_set = set(X_df.columns)

missing = saved_feature_set - current_feature_set
extra = current_feature_set - saved_feature_set

if missing:
    print(f"   ⚠️ Missing features (adding zeros): {len(missing)}")
    if len(missing) <= 10:
        print(f"      {list(missing)}")
    # Add missing columns efficiently using pd.concat
    missing_df = pd.DataFrame(0, index=X_df.index, columns=list(missing))
    X_df = pd.concat([X_df, missing_df], axis=1)

if extra:
    print(f"   ℹ️ Extra features (removing): {len(extra)}")
    if len(extra) <= 10:
        print(f"      {list(extra)}")

# Reorder columns to match saved model
X_df = X_df[feature_names]

# Convert to numpy
X = X_df.values.astype(np.float32)
y = np.array(y_list)

# Encode labels
y_encoded = label_encoder.transform(y)
num_classes = len(label_encoder.classes_)

print(f"   Final shape: X={X.shape}, y={y_encoded.shape}")
print(f"   Classes: {num_classes}")

# Scale features using saved scaler
X_scaled = scaler.transform(X).astype(np.float32)

# ============================================================================
# STEP 4: Validate sklearn model on this data
# ============================================================================

print("\n📊 Step 4: Validating scikit-learn model accuracy...")

from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score, f1_score

X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)

sklearn_preds = sklearn_model.predict(X_test)
sklearn_acc = accuracy_score(y_test, sklearn_preds)
sklearn_f1 = f1_score(y_test, sklearn_preds, average='weighted')

print(f"   Scikit-learn Model Accuracy: {sklearn_acc:.4f}")
print(f"   Scikit-learn Model F1-Score: {sklearn_f1:.4f}")
print(f"\n   Classification Report:")
print(classification_report(
    y_test, sklearn_preds,
    target_names=[ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_]
))

# ============================================================================
# STEP 5: Train TensorFlow/Keras Neural Network
# ============================================================================

print("\n🧠 Step 5: Training TensorFlow/Keras neural network...")

import tensorflow as tf
from tensorflow import keras

# One-hot encode labels for training
y_train_onehot = keras.utils.to_categorical(y_train, num_classes)
y_test_onehot = keras.utils.to_categorical(y_test, num_classes)

# Build the model
input_dim = X_train.shape[1]

model = keras.Sequential([
    keras.layers.Input(shape=(input_dim,)),
    keras.layers.Dense(256, activation='relu'),
    keras.layers.BatchNormalization(),
    keras.layers.Dropout(0.3),
    keras.layers.Dense(128, activation='relu'),
    keras.layers.BatchNormalization(),
    keras.layers.Dropout(0.3),
    keras.layers.Dense(64, activation='relu'),
    keras.layers.BatchNormalization(),
    keras.layers.Dropout(0.2),
    keras.layers.Dense(32, activation='relu'),
    keras.layers.Dense(num_classes, activation='softmax')
])

model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

print(f"\n   Model Summary:")
model.summary()

# Knowledge distillation: use sklearn predictions as soft labels
print("\n   Training with knowledge distillation from sklearn model...")
sklearn_train_probs = sklearn_model.predict_proba(X_train).astype(np.float32)

# Train first with sklearn soft labels (knowledge distillation)
model.fit(
    X_train, sklearn_train_probs,
    validation_data=(X_test, y_test_onehot),
    epochs=30,
    batch_size=64,
    verbose=1,
    callbacks=[
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=3),
    ]
)

# Fine-tune with actual labels
print("\n   Fine-tuning with true labels...")
model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.0005),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

model.fit(
    X_train, y_train_onehot,
    validation_data=(X_test, y_test_onehot),
    epochs=30,
    batch_size=64,
    verbose=1,
    callbacks=[
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=3),
    ]
)

# Evaluate Keras model
keras_preds = np.argmax(model.predict(X_test), axis=1)
keras_acc = accuracy_score(y_test, keras_preds)
keras_f1 = f1_score(y_test, keras_preds, average='weighted')

print(f"\n   Keras Model Accuracy: {keras_acc:.4f}")
print(f"   Keras Model F1-Score: {keras_f1:.4f}")
print(f"\n   Classification Report:")
print(classification_report(
    y_test, keras_preds,
    target_names=[ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_]
))

# Save Keras model
keras_model_path = OUTPUT_DIR / "har_keras_model.keras"
model.save(str(keras_model_path))
print(f"   ✅ Keras model saved: {keras_model_path}")

# ============================================================================
# STEP 6: Convert to TFLite
# ============================================================================

print("\n📱 Step 6: Converting to TFLite...")

# Standard conversion (float32)
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

tflite_path = OUTPUT_DIR / "har_model.tflite"
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)

tflite_size = os.path.getsize(tflite_path) / 1024
print(f"   ✅ Float32 TFLite model: {tflite_path}")
print(f"      Size: {tflite_size:.1f} KB")

# Quantized conversion (INT8) - smaller model
converter_quant = tf.lite.TFLiteConverter.from_keras_model(model)
converter_quant.optimizations = [tf.lite.Optimize.DEFAULT]

# Use representative dataset for full integer quantization
def representative_dataset():
    for i in range(min(500, len(X_train))):
        yield [X_train[i:i+1]]

converter_quant.representative_dataset = representative_dataset
converter_quant.target_spec.supported_types = [tf.float16]

tflite_quant_model = converter_quant.convert()

tflite_quant_path = OUTPUT_DIR / "har_model_quantized.tflite"
with open(tflite_quant_path, 'wb') as f:
    f.write(tflite_quant_model)

tflite_quant_size = os.path.getsize(tflite_quant_path) / 1024
print(f"   ✅ Quantized TFLite model: {tflite_quant_path}")
print(f"      Size: {tflite_quant_size:.1f} KB")
print(f"      Compression: {(1 - tflite_quant_size/tflite_size)*100:.1f}% smaller")

# ============================================================================
# STEP 7: Validate TFLite Model
# ============================================================================

print("\n✅ Step 7: Validating TFLite model accuracy...")

def run_tflite_inference(tflite_path, X_data):
    """Run inference using TFLite interpreter."""
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

# Test float32 model
print("\n   Testing Float32 TFLite model...")
tflite_preds = run_tflite_inference(tflite_path, X_test)
tflite_acc = accuracy_score(y_test, tflite_preds)
tflite_f1 = f1_score(y_test, tflite_preds, average='weighted')

print(f"   Float32 TFLite Accuracy: {tflite_acc:.4f}")
print(f"   Float32 TFLite F1-Score: {tflite_f1:.4f}")

# Test quantized model
print("\n   Testing Quantized TFLite model...")
tflite_quant_preds = run_tflite_inference(tflite_quant_path, X_test)
tflite_quant_acc = accuracy_score(y_test, tflite_quant_preds)
tflite_quant_f1 = f1_score(y_test, tflite_quant_preds, average='weighted')

print(f"   Quantized TFLite Accuracy: {tflite_quant_acc:.4f}")
print(f"   Quantized TFLite F1-Score: {tflite_quant_f1:.4f}")

# ============================================================================
# STEP 8: Summary Comparison
# ============================================================================

print("\n" + "=" * 70)
print("📊 FINAL COMPARISON")
print("=" * 70)

results = pd.DataFrame({
    'Model': ['Scikit-Learn (Original)', 'Keras (Neural Net)', 'TFLite (Float32)', 'TFLite (Quantized)'],
    'Accuracy': [sklearn_acc, keras_acc, tflite_acc, tflite_quant_acc],
    'F1-Score': [sklearn_f1, keras_f1, tflite_f1, tflite_quant_f1],
    'Size': [
        f"{os.path.getsize(model_dir / 'model.joblib') / 1024:.1f} KB",
        f"{os.path.getsize(keras_model_path) / 1024:.1f} KB",
        f"{tflite_size:.1f} KB",
        f"{tflite_quant_size:.1f} KB"
    ],
    'Mobile Ready': ['❌ No', '❌ No', '✅ Yes', '✅ Yes']
})

print(results.to_string(index=False))

# ============================================================================
# STEP 9: Save metadata for Flutter integration
# ============================================================================

print("\n📋 Step 9: Saving metadata for Flutter integration...")

metadata = {
    'model_name': MODEL_TO_CONVERT,
    'num_features': input_dim,
    'feature_names': list(feature_names),
    'num_classes': num_classes,
    'class_labels': list(label_encoder.classes_),
    'class_names': [ACTIVITY_LABELS.get(c, c) for c in label_encoder.classes_],
    'window_size': WINDOW_SIZE,
    'sampling_rate_hz': 20,
    'overlap': OVERLAP,
    'scaler_mean': scaler.mean_.tolist(),
    'scaler_scale': scaler.scale_.tolist(),
    'sklearn_accuracy': float(sklearn_acc),
    'keras_accuracy': float(keras_acc),
    'tflite_accuracy': float(tflite_acc),
    'tflite_quant_accuracy': float(tflite_quant_acc),
}

import json
metadata_path = OUTPUT_DIR / "model_metadata.json"
with open(metadata_path, 'w') as f:
    json.dump(metadata, f, indent=2)

print(f"   ✅ Metadata saved: {metadata_path}")

# Also save scaler separately for Flutter
scaler_data = {
    'mean': scaler.mean_.tolist(),
    'scale': scaler.scale_.tolist(),
}
scaler_path = OUTPUT_DIR / "scaler_params.json"
with open(scaler_path, 'w') as f:
    json.dump(scaler_data, f, indent=2)

print(f"   ✅ Scaler params saved: {scaler_path}")

print("\n" + "=" * 70)
print("🎉 Phase 1.5 Complete!")
print("=" * 70)
print(f"\n   Output files in: {OUTPUT_DIR}")
print(f"   1. har_model.tflite          — Float32 model for Flutter")
print(f"   2. har_model_quantized.tflite — Smaller quantized model")
print(f"   3. model_metadata.json       — Feature names, classes, config")
print(f"   4. scaler_params.json        — Scaler mean/scale for preprocessing")
print(f"   5. har_keras_model.keras      — Keras model (backup)")
print(f"\n   Next: Copy .tflite + .json files to Flutter assets folder")
print(f"         and use tflite_flutter package for on-device inference.")
