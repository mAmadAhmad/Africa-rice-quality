# Rice Quality Assessor

I took on a coding challenge and built a fully offline Android app that runs rice quality assessment using a ConvNeXt-Small model that I finetuned — entirely on-device. Built for the [Zindi AfricaRice Quality Assessment Challenge](https://zindi.africa), where the core requirement was a working field tool for farmers, rice traders etc in areas without reliable internet.

**Final standing: 22nd out of 50 teams/individuals — public score 0.755 · [competition leaderboard](https://zindi.africa/competitions/unido-africarice-app-builder-challenge/leaderboard)**
---

## What it does

Take a picture of rice grains on a blue background, press capture, and ~32 seconds later get:
- Total grain count with how many are broken/long/medium, Dimensions of grains like avg length, width, L/W ratio, Defects like how many grains are chalky, black, red, yellow, or green and CIELAB colour profile (L\*, a\*, b\*), so the farmers and traders can do an informed descision and quickly assess what tier the rice belong to. This is an early quick assessment tool not something you solely rely on.
---

## Finetuning the model 

The model is a ConvNeXt-Small backbone with 9 independent MultiScale CSR density heads (one per grain category) and a regression head for morphological measurements provided to us by Zindi along with the documentation and link to data source so we could finetune it for mobile.

The original model was trained on a 6×8 tile grid (the image was split into 48 chunks and then assessed) the model won 3rd place in previous competition and had near 1-2 MAE. The challenge was it took more than 5 minutes on my A52 (a midrange phone with 8gigs of ram) but we cannot use it this way as the app was supposed to run on low end devices too 3-4 gigs of ram so we cannot cram this 220MB model, the images it scans into ram. As app will stop responding again and again.

First I quantized it to int-8 (which was a challenge in itself as much math functions in float32 couldn't be quantized for lack of support on mobile tf and onnx library), this version also took 3 minutes way over the 60-second field usability target and went to 10-14 MAE. The issue here was, we were still running the model on 48 chunks so 48 model inferences on each image takes time.

Then to decrease how many times the model runs I fine-tuned the original model down to a 3×4 grid (now the image will be splitted into 12 chunks so only 12 model inferences, easy on low end phones). I used a two-phase gradual unfreezing strategy:
1. Freeze the backbone, train only the density heads for 7 epochs so they recalibrate to the new 3x4 tile grid and do not forget what it had learned like in simple words how rice looked, how to calculate dimensions, just changed the input style.
2. After epoch 7 unfreeze the full model at 10× lower LR so model can slowly converge and then I quantized it to int-8 so it is easy to run on mobile cpus.

This got the inference time down to ~32 seconds while keeping accuracy in 17-18 MAE range.

**Final validation MAE: ~17.9 grains across 9 categories campared to 10-12 MAE of original models int-8 quantized version**

---

## How I made it fast on mobile why I didn't used the mobile gpu to accelerate the inference on original model

The mobile gpu library does not support all the mathematical functions, so it was offloading computation to cpu and this back and forth exchange made an overhead per tile. Per image tile/chunk (the original 48 chunks and the new finetuned 12 chunks) it took 4 - 4.7 secs. This made me switch solely to run it on CPU using XNNPACK (enables multi-threaded CPU execution), Luckily it cut the time in half, now per tile execution took 2 - 2.2 secs. So our new 12 tiles took 12x2 = 24s and accounting for image preprocessing the whole inference took 32 - 35 secs.
And this preprocessing & inference stays in a background function with model loaded at app startup so no stutters on main thread. 

Other than that AI helped me optimize ram usage with these preprocessing techniques:

LUT normalisation: instead of computing `(pixel / 255.0 - mean) / std` per pixel, pre-compute all 256 possible values for each channel into lookup tables at isolate startup. Makes normalising 786,432 values per tile much faster.

Inline nearest-neighbour resize: tile extraction resizes each block directly into the `Float32List` tensor buffer by sampling the raw RGBA bytes with integer scaling arithmetic. No intermediate `Image` object is allocated per tile — zero heap pressure in the inference loop.

---

## Tech stack
- **Python / PyTorch / timm** — model training and fine-tuning (code not included here), I had to run back and forth on multiple google colab sessions to run the finetuning untill training loss plateaued
- **Flutter / Dart** — frontend and isolate architecture
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

Tested on Samsung Galaxy A52 (Snapdragon 720G, Android 14).

---

## Notes

I used AI for flutter development as I do not have a prior experience with mobile application development.

The model IP is co-owned by UNIDO and AfricaRice per competition guidelines. The app is built entirely on open-source tools and is intended for non-commercial field assessment use.

Medium grain count (`Medium_Count`) consistently predicts near zero — this is a data issue, not a model bug. The training distribution is ~80% zero for this category, so the model learns that predicting zero minimises loss. Garbage in, garbage out.