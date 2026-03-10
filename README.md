# AfricaRice Quality Assessor (Edge ML)

An offline-first Flutter application built for the Zindi AfricaRice Quality Assessment Challenge. This app runs a native, INT8-quantized ConvNeXt-Small computer vision model directly on edge devices (Android/iOS) using ONNX Runtime Mobile and XNNPACK acceleration.

## 🚀 Key Features
* **Fully Offline Inference:** No cloud APIs. 100% of the ML processing happens on-device.
* **Smart Image Validation:** Pre-inference checks for pixel luminance (darkness) and Laplacian variance (motion blur) to save compute.
* **Dynamic Tensor Routing:** Dynamically adjusts the one-hot metadata tensor `[Paddy, White, Brown]` based on user selection to correctly condition the model's multi-scale decoder.
* **12-Tile Grid Processing:** Slices 4K camera input into a 3x4 non-overlapping grid to manage mobile RAM constraints while matching the model's native training resolution.
* **Field-Ready Export:** Generates detailed CSV reports including 9 grain counts, 6 measurement metrics, and GPS coordinates for agronomist traceability.

## 🛠️ Tech Stack
* **Frontend:** Flutter / Dart
* **Inference Engine:** ONNX Runtime Mobile (C++ backend via FFI)
* **Local Storage:** SQLite (`sqflite`)
* **Hardware Interfacing:** `camera`, `geolocator`

## 📂 Project Structure
* `/lib/`
  * `camera_screen.dart`: UI for capture, GPS fetching, and Rice Type selection.
  * `inference_service.dart`: Background Isolate running the ONNX model.
  * `rice_logic.dart`: Post-processing, thresholding, and grading logic.
  * `export_screen.dart`: SQLite to CSV generation.
* `/assets/`
  * `convnext_3x4_int8.onnx`: The quantized model weights.
* `/python_scripts/`
  * `benchmark.py`: Scripts used to verify ONNX tensor outputs against Python baselines.

## ⚙️ How to Build and Run
1. Ensure Flutter is installed (v3.10+ recommended).
2. Clone the repository.
3. Run `flutter pub get` to install dependencies.
4. Ensure an Android device or emulator is connected.
5. Run `flutter run --release` (Note: Inference runs significantly faster in release mode due to Dart AOT compilation and XNNPACK threading).

## 🧠 Model Architecture Note
The underlying model utilizes a multi-scale CSR Decoder. To prevent the mobile device from running out of memory on 12-megapixel camera images, the `inference_service.dart` handles inline nearest-neighbor resizing, converting image blocks directly into `[1, 1, 3, 512, 512]` `Float32List` buffers without instantiating intermediate objects in memory.