# AfricaRice Quality Assessor

A fully offline Android app that runs rice quality assessment using a fine-tuned ConvNeXt-Small model — entirely on-device. Built for the [Zindi AfricaRice Quality Assessment Challenge](https://zindi.africa), where the core requirement was a working field tool for agronomists in areas without reliable internet.

**Final standing: 22nd out of 50 teams/individuals — public score 0.755 · [competition leaderboard](https://zindi.africa/competitions/unido-africarice-app-builder-challenge/leaderboard)**
---

## What it does

You point your phone camera at a tray of rice grains, press capture, and ~32 seconds later get:

- Total grain count with broken/long/medium breakdown
- Milling grade (Premium → Grade 3 based on broken %)
- Kernel dimensions (avg length, width, L/W ratio)
- Defect flags — chalky, black, red, yellow, green grain counts
- CIELAB colour profile (L\*, a\*, b\*)
- Optional GPS coordinates attached to the scan

Everything runs offline. No API calls, no cloud inference, no internet required.

---

## The ML side

The model is a ConvNeXt-Small backbone with 9 independent MultiScale CSR density heads (one per grain category) and a regression head for morphological measurements.

The original model was trained on a 6×8 tile grid (48 tiles per image), which gave good accuracy but took ~216 seconds on a mid-range phone — way over the 60-second field usability target. I fine-tuned it down to a 3×4 grid (12 tiles) using a two-phase gradual unfreezing strategy:

1. Freeze the backbone, train only the density heads for 7 epochs so they recalibrate to the new tile scale without corrupting the pretrained features
2. Unfreeze the full model at 10× lower LR for end-to-end refinement

This got the inference time down to ~32 seconds while keeping accuracy in a usable range. The model is then exported to ONNX and quantized to INT8, bringing it from 218MB to 55.6MB.

**Final validation MAE: ~17.9 grains across 9 categories**

---

## Why it's fast on mobile

A few things that made a real difference:

**XNNPACK** — enables multi-threaded CPU execution via ONNX Runtime's execution provider. Cuts per-tile latency roughly in half on Snapdragon devices (~2.2s vs ~4.3s per tile).

**LUT normalisation** — instead of computing `(pixel / 255.0 - mean) / std` per pixel, I pre-compute all 256 possible values for each channel into lookup tables at isolate startup. Makes normalising 786,432 values per tile much faster.

**Inline nearest-neighbour resize** — tile extraction resizes each block directly into the `Float32List` tensor buffer by sampling the raw RGBA bytes with integer scaling arithmetic. No intermediate `Image` object is allocated per tile — zero heap pressure in the inference loop.

**Background isolate** — the entire ONNX session lives in a Dart isolate spawned at app launch, pre-warmed before the user reaches the camera. The main thread stays unblocked so the progress bar and UI remain responsive during inference.

---

## Tech stack

- **Flutter / Dart** — frontend and isolate architecture
- **ONNX Runtime Mobile** — C++ inference backend via FFI
- **XNNPACK** — multi-threaded CPU execution provider
- **SQLite (sqflite)** — local scan history
- **Geolocator** — optional field GPS tagging
- **Python / PyTorch / timm** — model training and fine-tuning (code not included here)

---

## Project structure

```
lib/
├── main.dart                 # App entry, isolate warm-up, routing
├── inference_service.dart    # Background isolate, tile loop, ONNX session
├── rice_logic.dart           # Grading thresholds, percentage calculations
├── camera_screen.dart        # Capture, GPS fetch, rice type selection
├── results_screen.dart       # Full metrics display
├── history_screen.dart       # SQLite scan history list
├── export_screen.dart        # CSV generation and share sheet
├── database_helper.dart      # SQLite schema and queries
├── home_screen.dart          # Dashboard and capture guidelines
├── profile_screen.dart       # User preferences and GPS opt-in
├── signup_screen.dart        # First-launch onboarding
├── disclaimer_screen.dart    # IP disclaimer (UNIDO / AfricaRice)
└── app_info_screen.dart      # Model version and data policy

assets/
└── convnext_3x4_int8.onnx    # INT8 quantized model (55.6 MB)
```

---

## Running it

```bash
git clone <repo>
cd rice_quality_app
flutter pub get
flutter run --release
```

Use `--release` — inference runs noticeably faster with Dart AOT compilation and ONNX Runtime release optimisations enabled.

Tested on Samsung Galaxy A52 (Snapdragon 720G, Android 14).

---

## Notes

The model IP is co-owned by UNIDO and AfricaRice per competition guidelines. The app is built entirely on open-source tools and is intended for non-commercial field assessment use.

Medium grain count (`Medium_Count`) consistently predicts near zero — this is a data issue, not a model bug. The training distribution is ~80% zero for this category, so the model learns that predicting zero minimises loss. Garbage in, garbage out.