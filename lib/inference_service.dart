import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Manages on-device rice quality inference using a fine-tuned ConvNeXt-Small
/// model exported to ONNX and quantized to INT8 (55.6 MB).
///
/// ## Model architecture
/// ConvNeXt-Small backbone with 9 independent MultiScaleCSR density-map heads
/// (one per grain category) and a morphological measurement regression head.
/// Trained on a 3-row × 4-column non-overlapping tile grid (12 tiles per image).
/// Fine-tuned from a competition-winning checkpoint using a two-phase strategy:
/// backbone frozen for 7 epochs, then unfrozen at 10× lower LR for end-to-end
/// refinement. Final validation MAE: ~17.9 grains across 9 categories.
///
/// ## Inference pipeline
/// 1. Decode image → optional downsample to 4000px → quality validation
/// 2. Divide image into 12 non-overlapping tiles via integer grid arithmetic
/// 3. Inline nearest-neighbour resize each tile to 512×512 (no intermediate alloc)
/// 4. Normalise pixels via pre-computed LUT → build rank-5 ONNX input tensor
/// 5. Run ONNX session with XNNPACK acceleration → accumulate outputs
/// 6. Descale counts ÷ 100 → average measures → apply rice-type zeroing rules
///
/// ## Isolate design
/// All ONNX work runs in a dedicated background [Isolate] spawned once at [init].
/// The main thread communicates via [SendPort]/[ReceivePort] message passing.
/// This keeps the UI fully responsive during the ~32-second inference window
/// and avoids Flutter's platform-channel restrictions that would block GPS and
/// camera APIs if inference ran on the main thread.
///
/// ## Singleton
/// One instance is shared app-wide so the ONNX session is compiled once and
/// reused across scans without repeated 1.2-second cold-start overhead.
class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  SendPort? _workerCommandPort;
  bool isReady = false;

  /// Spawns the background isolate and loads the ONNX model into it.
  /// Called at app launch so the model is warm by the time the user
  /// reaches the camera screen. Safe to call multiple times — no-op if ready.
  Future<void> init() async {
    if (isReady) return;

    final receivePort = ReceivePort();
    final modelBytes  = await rootBundle.load('assets/convnext_3x4_int8.onnx');

    await Isolate.spawn(
      _workerIsolate,
      [receivePort.sendPort, modelBytes.buffer.asUint8List()],
    );

    _workerCommandPort = await receivePort.first as SendPort;
    isReady = true;
  }

  /// Submits an image to the background isolate for inference.
  ///
  /// [imagePath]  — absolute path to the captured or gallery image.
  /// [riceType]   — 'White', 'Paddy', or 'Brown'. Determines the one-hot
  ///                meta tensor fed to the model and which output categories
  ///                are zeroed during post-processing.
  /// [onProgress] — optional callback fired after each of the 12 tiles,
  ///                used to update the UI progress bar (tile, total).
  ///
  /// Returns a flat [Map] of all count, measure, and timing fields, or a map
  /// with 'validation_failed': true if the image fails quality checks.
  Future<Map<String, dynamic>> analyzeImage(
    String imagePath, {
    required String riceType,
    Function(int, int)? onProgress,
  }) async {
    if (!isReady) throw Exception("Model is still initializing.");

    final responsePort = ReceivePort();
    _workerCommandPort!.send([imagePath, responsePort.sendPort, riceType]);

    await for (final message in responsePort) {
      if (message is Map && message['status'] == 'progress') {
        onProgress?.call(message['tile'], message['total']);
      } else {
        responsePort.close();
        return message as Map<String, dynamic>;
      }
    }
    throw Exception("Worker closed unexpectedly");
  }

  // ---------------------------------------------------------------------------
  // Background isolate — everything below runs permanently off the main thread.
  // ---------------------------------------------------------------------------

  static void _workerIsolate(List<dynamic> args) {
    final SendPort mainSendPort = args[0];
    final Uint8List modelBytes  = args[1];

    // Pre-compute per-channel normalisation lookup tables (ImageNet statistics).
    // Converts per-pixel normalisation from float arithmetic to a single array
    // lookup — measurably faster when applied across 3×512×512 = 786,432 values.
    const mean = [0.485, 0.456, 0.406];
    const std  = [0.229, 0.224, 0.225];
    final lutR = Float32List(256);
    final lutG = Float32List(256);
    final lutB = Float32List(256);
    for (int i = 0; i < 256; i++) {
      lutR[i] = (i / 255.0 - mean[0]) / std[0];
      lutG[i] = (i / 255.0 - mean[1]) / std[1];
      lutB[i] = (i / 255.0 - mean[2]) / std[2];
    }

    // Initialise ONNX Runtime. XNNPACK enables multi-threaded CPU execution,
    // roughly halving per-tile latency on Snapdragon devices (~2.2s vs ~4.3s).
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    String accelerator = "Standard CPU";
    try {
      sessionOptions.appendXnnpackProvider();
      accelerator = "XNNPACK (Multi-Threaded CPU)";
    } catch (_) {
      // XNNPACK unavailable — continue with standard single-threaded EP.
    }

    final initStopwatch = Stopwatch()..start();
    final session    = OrtSession.fromBuffer(modelBytes, sessionOptions);
    final runOptions = OrtRunOptions();
    initStopwatch.stop();
    final initTime = (initStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(2);

    // Signal the main isolate that the session is compiled and ready.
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    commandPort.listen((message) {
      final String imagePath   = message[0];
      final SendPort replyPort = message[1];
      final String riceTypeStr = message[2];

      final totalStopwatch = Stopwatch()..start();
      int totalInferenceMs  = 0;
      int totalPreprocessMs = 0;

      try {
        // ── Step 1: Decode and optionally downsample ─────────────────────────
        // Cap width at 4000px to bound memory during tile extraction while
        // preserving enough resolution for accurate density estimation.
        final preStopwatch = Stopwatch()..start();
        img.Image workingImage = img.decodeImage(
          File(imagePath).readAsBytesSync(),
        )!;
        if (workingImage.width > 4000 || workingImage.height > 4000) {
          workingImage = img.copyResize(workingImage, width: 4000);
        }

        // ── Step 2: Image quality validation ─────────────────────────────────
        // Runs on a 256px thumbnail to avoid processing full-resolution data.
        // Brightness: mean luminance < 30 → image too dark for reliable inference.
        // Blur: Laplacian variance < 50 → motion blur or out-of-focus capture.
        // Both checks run before any model inference to conserve compute.
        final evalImg = img.copyResize(workingImage, width: 256);
        double totalLuminance = 0;
        double laplacianSum   = 0;
        double laplacianSqSum = 0;
        int    lapCount       = 0;

        for (int y = 1; y < evalImg.height - 1; y++) {
          for (int x = 1; x < evalImg.width - 1; x++) {
            final p   = evalImg.getPixel(x, y);
            final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
            totalLuminance += lum;

            final lum01 = 0.299 * evalImg.getPixel(x, y-1).r + 0.587 * evalImg.getPixel(x, y-1).g + 0.114 * evalImg.getPixel(x, y-1).b;
            final lum10 = 0.299 * evalImg.getPixel(x-1, y).r + 0.587 * evalImg.getPixel(x-1, y).g + 0.114 * evalImg.getPixel(x-1, y).b;
            final lum12 = 0.299 * evalImg.getPixel(x+1, y).r + 0.587 * evalImg.getPixel(x+1, y).g + 0.114 * evalImg.getPixel(x+1, y).b;
            final lum21 = 0.299 * evalImg.getPixel(x, y+1).r + 0.587 * evalImg.getPixel(x, y+1).g + 0.114 * evalImg.getPixel(x, y+1).b;

            final laplacian = lum01 + lum10 + lum12 + lum21 - (4 * lum);
            laplacianSum   += laplacian;
            laplacianSqSum += laplacian * laplacian;
            lapCount++;
          }
        }

        final avgBrightness = totalLuminance / (evalImg.width * evalImg.height);
        final lapMean       = laplacianSum / lapCount;
        final blurVariance  = (laplacianSqSum / lapCount) - (lapMean * lapMean);

        if (avgBrightness < 30.0) {
          replyPort.send({'validation_failed': true, 'reason': 'Image is too dark. Please use better lighting.'});
          return;
        }
        if (blurVariance < 50.0) {
          replyPort.send({'validation_failed': true, 'reason': 'Image is too blurry. Please hold the camera steady.'});
          return;
        }

        // ── Step 3: Tile grid setup ───────────────────────────────────────────
        // 3-row × 4-column non-overlapping grid matching the training configuration.
        // Each tile covers a distinct region — no grain is counted more than once.
        // The last tile in each axis absorbs remainder pixels to ensure 100% coverage.
        const int tileSize   = 512;
        const int gridCols   = 4;
        const int gridRows   = 3;
        const int totalTiles = gridRows * gridCols; // 12

        final Uint8List fullRawBytes = workingImage.getBytes(order: img.ChannelOrder.rgba);
        final int fullWidth  = workingImage.width;
        final int fullHeight = workingImage.height;
        final int stepX      = fullWidth  ~/ gridCols;
        final int stepY      = fullHeight ~/ gridRows;

        preStopwatch.stop();
        totalPreprocessMs += preStopwatch.elapsedMilliseconds;

        // ── Step 4: Rice-type one-hot meta tensor ─────────────────────────────
        // A [1, 3] one-hot vector conditions the model's density heads on grain
        // morphology appropriate for the selected variety. This matches the
        // 'Comment' column encoding used during training: Paddy=0, White=1, Brown=2.
        late Float32List metaData;
        int riceTypeIndex;
        switch (riceTypeStr) {
          case 'Paddy':
            metaData = Float32List.fromList([1.0, 0.0, 0.0]); riceTypeIndex = 0; break;
          case 'Brown':
            metaData = Float32List.fromList([0.0, 0.0, 1.0]); riceTypeIndex = 2; break;
          default: // White
            metaData = Float32List.fromList([0.0, 1.0, 0.0]); riceTypeIndex = 1;
        }
        final metaTensor = OrtValueTensor.createTensorWithDataList(metaData, [1, 3]);

        // Single reusable CHW buffer, overwritten each tile to avoid 12 allocations.
        final imgData = Float32List(3 * tileSize * tileSize);

        final totalCounts   = List.filled(9, 0.0);
        final totalMeasures = List.filled(6, 0.0);

        // ── Step 5: Tile inference loop ───────────────────────────────────────
        for (int r = 0; r < gridRows; r++) {
          for (int c = 0; c < gridCols; c++) {
            final loopPreStopwatch = Stopwatch()..start();

            final int startX = c * stepX;
            final int startY = r * stepY;
            final int endX   = (c == gridCols - 1) ? fullWidth  : (c + 1) * stepX;
            final int endY   = (r == gridRows - 1) ? fullHeight : (r + 1) * stepY;
            final int blockW = endX - startX;
            final int blockH = endY - startY;

            // Inline nearest-neighbour resize directly into the CHW tensor buffer.
            // Samples source RGBA bytes using integer scaling — no intermediate
            // img.Image allocation per tile, zero heap pressure in the hot loop.
            final int rOffset = 0 * tileSize * tileSize;
            final int gOffset = 1 * tileSize * tileSize;
            final int bOffset = 2 * tileSize * tileSize;

            for (int py = 0; py < tileSize; py++) {
              final int srcY    = startY + (py * blockH) ~/ tileSize;
              final int yOffset = srcY * fullWidth;
              for (int px = 0; px < tileSize; px++) {
                final int srcX       = startX + (px * blockW) ~/ tileSize;
                final int byteIndex  = (yOffset + srcX) * 4; // RGBA: 4 bytes/pixel
                final int pixelIndex = py * tileSize + px;
                imgData[rOffset + pixelIndex] = lutR[fullRawBytes[byteIndex]];
                imgData[gOffset + pixelIndex] = lutG[fullRawBytes[byteIndex + 1]];
                imgData[bOffset + pixelIndex] = lutB[fullRawBytes[byteIndex + 2]];
              }
            }

            // Rank-5 input: [batch=1, N=1, C=3, H=512, W=512].
            // The extra N dimension matches the training forward pass signature
            // (batch × tiles × C × H × W) preserved through ONNX export.
            final imageTensor = OrtValueTensor.createTensorWithDataList(
              imgData, [1, 1, 3, tileSize, tileSize],
            );
            loopPreStopwatch.stop();
            totalPreprocessMs += loopPreStopwatch.elapsedMilliseconds;

            final infStopwatch = Stopwatch()..start();
            final outputs = session.run(
              runOptions,
              {'image_tile': imageTensor, 'rice_type': metaTensor},
            );
            infStopwatch.stop();
            totalInferenceMs += infStopwatch.elapsedMilliseconds;

            replyPort.send({
              'status': 'progress',
              'tile':   (r * gridCols) + c + 1,
              'total':  totalTiles,
            });

            final outNames = session.outputNames;
            for (int i = 0; i < outputs.length; i++) {
              final List<dynamic> vals = (outputs[i]?.value as List)[0];
              if (outNames[i] == 'counts') {
                for (int j = 0; j < 9; j++) totalCounts[j]   += (vals[j] as num).toDouble();
              } else if (outNames[i] == 'measures') {
                for (int j = 0; j < 6; j++) totalMeasures[j] += (vals[j] as num).toDouble();
              }
            }

            imageTensor.release();
            for (final o in outputs) { o?.release(); }
          }
        }

        metaTensor.release();

        // ── Step 6: Post-processing ───────────────────────────────────────────
        // Counts: divide by training scale factor (100). Targets were multiplied
        // by 100 during training for gradient stability — reverse that here.
        // 12 tiles cover 100% of the image so no extrapolation factor is applied.
        for (int i = 0; i < 9; i++) totalCounts[i] /= 100.0;

        // Measures: average across tiles, then un-normalise with training stats.
        for (int i = 0; i < 6; i++) totalMeasures[i] /= totalTiles;

        // Zero grain categories that are biologically inapplicable for the
        // selected rice type, replicating post-processing applied during training.
        if (riceTypeIndex == 0) {       // Paddy — pre-milling, chalky/medium/yellow/green N/A
          totalCounts[3] = 0.0;         // Medium_Count
          totalCounts[5] = 0.0;         // Chalky_Count
          totalCounts[7] = 0.0;         // Yellow_Count
          totalCounts[8] = 0.0;         // Green_Count
        } else if (riceTypeIndex == 2) { // Brown — hulled but unmilled; green grains N/A
          totalCounts[8] = 0.0;          // Green_Count
        }

        // Un-normalise morphological measurements using training dataset statistics.
        const measureMeans = [7.648381233215332, 2.564115285873413, 3.064692735671997,
                              64.19993591308594, 2.807239532470703, 15.470088005065918];
        const measureStds  = [1.2248483896255493, 0.3781449496746063, 0.34657320380210876,
                              6.3935770988464355, 5.4505696296691895, 14.535634994506836];
        for (int i = 0; i < 6; i++) {
          totalMeasures[i] = (totalMeasures[i] * measureStds[i]) + measureMeans[i];
        }

        // ── Step 7: Send results to main isolate ──────────────────────────────
        totalStopwatch.stop();
        final totalSec = (totalStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(2);
        final infSec   = (totalInferenceMs  / 1000.0).toStringAsFixed(2);
        final preSec   = (totalPreprocessMs / 1000.0).toStringAsFixed(2);

        double sanitize(double val) => (val.isNaN || val.isInfinite) ? 0.0 : val;

        replyPort.send({
          // Grain counts — absolute values, not percentages
          'Total_Count':  sanitize(totalCounts[0]),
          'Broken_Count': sanitize(totalCounts[1]),
          'Long_Count':   sanitize(totalCounts[2]),
          'Medium_Count': sanitize(totalCounts[3]),
          'Black_Count':  sanitize(totalCounts[4]),
          'Chalky_Count': sanitize(totalCounts[5]),
          'Red_Count':    sanitize(totalCounts[6]),
          'Yellow_Count': sanitize(totalCounts[7]),
          'Green_Count':  sanitize(totalCounts[8]),
          // Morphological measurements (mm and CIELAB)
          'Avg_Length':   sanitize(totalMeasures[0]),
          'Avg_Width':    sanitize(totalMeasures[1]),
          'LWR':          sanitize(totalMeasures[2]),
          'Avg_L':        sanitize(totalMeasures[3]),
          'Avg_A':        sanitize(totalMeasures[4]),
          'Avg_B':        sanitize(totalMeasures[5]),
          // Diagnostics
          'Accelerator':  accelerator,
          'Init_Time':    initTime,
          'Pre_Time':     preSec,
          'Inf_Time':     infSec,
          'Total_Time':   totalSec,
        });

      } catch (e) {
        replyPort.send({"error": e.toString()});
      }
    });
  }
}