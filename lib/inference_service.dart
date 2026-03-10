import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  SendPort? _workerCommandPort;
  bool isReady = false;

  Future<void> init() async {
    if (isReady) return;
    print("⚙️ [Main] Starting Persistent Background Worker...");

    final receivePort = ReceivePort();
    final modelBytes = await rootBundle.load('assets/convnext_3x4_int8.onnx');

    await Isolate.spawn(_workerIsolate, [receivePort.sendPort, modelBytes.buffer.asUint8List()]);

    _workerCommandPort = await receivePort.first as SendPort;
    isReady = true;
    print("✅ [Main] Background Worker is HOT and ready for images!");
  }

  // ── CHANGED: Added riceType parameter ──
  Future<Map<String, dynamic>> analyzeImage(String imagePath, {required String riceType, Function(int, int)? onProgress}) async {
    if (!isReady) throw Exception("Model is still initializing in the background.");

    final responsePort = ReceivePort();
    // Pass riceType to the isolate
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

  // ── EVERYTHING BELOW THIS LINE LIVES PERMANENTLY IN THE BACKGROUND ──
  static void _workerIsolate(List<dynamic> args) {
    final SendPort mainSendPort = args[0];
    final Uint8List modelBytes = args[1];

    print("🤖 [Worker] Booting up...");

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

    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    String accelerator = "CPU";

    try {
      sessionOptions.appendXnnpackProvider();
      accelerator = "XNNPACK (Multi-Threaded CPU)";
    } catch (e) {
      accelerator = "Standard CPU";
    }

    final initStopwatch = Stopwatch()..start();
    final session = OrtSession.fromBuffer(modelBytes, sessionOptions);
    final runOptions = OrtRunOptions();
    initStopwatch.stop();
    final initTime = (initStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(2);
    
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    commandPort.listen((message) {
      final String imagePath = message[0];
      final SendPort replyPort = message[1];
      final String riceTypeStr = message[2]; // ── CHANGED: Catch riceType

      final totalStopwatch = Stopwatch()..start();
      int totalInferenceMs = 0;
      int totalPreprocessMs = 0;

      try {
        final preStopwatch = Stopwatch()..start();
        final imageBytes = File(imagePath).readAsBytesSync();
        img.Image workingImage = img.decodeImage(imageBytes)!;

        if (workingImage.width > 4000 || workingImage.height > 4000) {
          workingImage = img.copyResize(workingImage, width: 4000);
        }

        // ── IMAGE VALIDATION (Blur & Brightness) ──
        img.Image evalImg = img.copyResize(workingImage, width: 256);
        double totalLuminance = 0;
        double laplacianSum = 0;
        double laplacianSqSum = 0;
        int lapCount = 0;

        for (int y = 1; y < evalImg.height - 1; y++) {
          for (int x = 1; x < evalImg.width - 1; x++) {
            final p11 = evalImg.getPixel(x, y);
            final lum11 = 0.299 * p11.r + 0.587 * p11.g + 0.114 * p11.b;
            totalLuminance += lum11;

            final p01 = evalImg.getPixel(x, y - 1);
            final p10 = evalImg.getPixel(x - 1, y);
            final p12 = evalImg.getPixel(x + 1, y);
            final p21 = evalImg.getPixel(x, y + 1);

            final lum01 = 0.299 * p01.r + 0.587 * p01.g + 0.114 * p01.b;
            final lum10 = 0.299 * p10.r + 0.587 * p10.g + 0.114 * p10.b;
            final lum12 = 0.299 * p12.r + 0.587 * p12.g + 0.114 * p12.b;
            final lum21 = 0.299 * p21.r + 0.587 * p21.g + 0.114 * p21.b;

            double laplacian = lum01 + lum10 + lum12 + lum21 - (4 * lum11);
            laplacianSum += laplacian;
            laplacianSqSum += laplacian * laplacian;
            lapCount++;
          }
        }

        double avgBrightness = totalLuminance / (evalImg.width * evalImg.height);
        double lapMean = laplacianSum / lapCount;
        double blurVariance = (laplacianSqSum / lapCount) - (lapMean * lapMean);

        if (avgBrightness < 30.0) {
          replyPort.send({'validation_failed': true, 'reason': 'Image is too dark. Please use better lighting.'});
          return;
        }
        if (blurVariance < 50.0) {
          replyPort.send({'validation_failed': true, 'reason': 'Image is too blurry. Please hold the camera steady.'});
          return;
        }

        const int tileSize = 512;
        final Uint8List fullRawBytes = workingImage.getBytes(order: img.ChannelOrder.rgba);
        final int fullWidth  = workingImage.width;
        final int fullHeight = workingImage.height;

        const int gridCols  = 4;
        const int gridRows  = 3;
        const int totalTiles = gridRows * gridCols;

        preStopwatch.stop();
        totalPreprocessMs += preStopwatch.elapsedMilliseconds;

        final int stepX = fullWidth  ~/ gridCols;
        final int stepY = fullHeight ~/ gridRows;

        final imgData  = Float32List(3 * tileSize * tileSize);
        
        // ── CHANGED: Dynamic MetaData Tensor ──
        late Float32List metaData;
        int riceTypeIndex = 1; // 1=White, 0=Paddy, 2=Brown
        if (riceTypeStr == 'Paddy') {
          metaData = Float32List.fromList([1.0, 0.0, 0.0]);
          riceTypeIndex = 0;
        } else if (riceTypeStr == 'Brown') {
          metaData = Float32List.fromList([0.0, 0.0, 1.0]);
          riceTypeIndex = 2;
        } else {
          metaData = Float32List.fromList([0.0, 1.0, 0.0]); // White
        }
        final metaTensor = OrtValueTensor.createTensorWithDataList(metaData, [1, 3]);

        List<double> totalCounts   = List.filled(9, 0.0);
        List<double> totalMeasures = List.filled(6, 0.0);

        for (int r = 0; r < gridRows; r++) {
          for (int c = 0; c < gridCols; c++) {

            final loopPreStopwatch = Stopwatch()..start();

            final int startX = c * stepX;
            final int startY = r * stepY;
            final int endX   = (c == gridCols - 1) ? fullWidth  : (c + 1) * stepX;
            final int endY   = (r == gridRows - 1) ? fullHeight : (r + 1) * stepY;
            final int blockW = endX - startX;
            final int blockH = endY - startY;

            final int rOffset = 0 * tileSize * tileSize;
            final int gOffset = 1 * tileSize * tileSize;
            final int bOffset = 2 * tileSize * tileSize;

            for (int py = 0; py < tileSize; py++) {
              final int srcY    = startY + (py * blockH) ~/ tileSize;
              final int yOffset = srcY * fullWidth;

              for (int px = 0; px < tileSize; px++) {
                final int srcX       = startX + (px * blockW) ~/ tileSize;
                final int byteIndex  = (yOffset + srcX) * 4;
                final int pixelIndex = py * tileSize + px;

                imgData[rOffset + pixelIndex] = lutR[fullRawBytes[byteIndex]];
                imgData[gOffset + pixelIndex] = lutG[fullRawBytes[byteIndex + 1]];
                imgData[bOffset + pixelIndex] = lutB[fullRawBytes[byteIndex + 2]];
              }
            }

            final imageTensor = OrtValueTensor.createTensorWithDataList(
                imgData, [1, 1, 3, tileSize, tileSize]); 
            loopPreStopwatch.stop();
            totalPreprocessMs += loopPreStopwatch.elapsedMilliseconds;

            final tileNum      = (r * gridCols) + c + 1;
            final infStopwatch = Stopwatch()..start();
            final inputs  = {'image_tile': imageTensor, 'rice_type': metaTensor};
            final outputs = session.run(runOptions, inputs);
            infStopwatch.stop();
            totalInferenceMs += infStopwatch.elapsedMilliseconds;

            replyPort.send({
              'status': 'progress',
              'tile':   tileNum,
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
            for (var o in outputs) { o?.release(); }
          }
        }

        metaTensor.release();

        for (int i = 0; i < 9; i++) totalCounts[i]   = totalCounts[i] / 100.0;
        for (int i = 0; i < 6; i++) totalMeasures[i] = totalMeasures[i] / totalTiles;

        // ── CHANGED: Apply Python Post-Processing Zeros ──
        if (riceTypeIndex == 0) { // Paddy
          totalCounts[3] = 0.0; // Medium_Count
          totalCounts[5] = 0.0; // Chalky_Count
          totalCounts[7] = 0.0; // Yellow_Count
          totalCounts[8] = 0.0; // Green_Count
        } else if (riceTypeIndex == 2) { // Brown
          totalCounts[8] = 0.0; // Green_Count
        }

        const measureMeans = [7.648381233215332, 2.564115285873413, 3.064692735671997,
                              64.19993591308594, 2.807239532470703, 15.470088005065918];
        const measureStds  = [1.2248483896255493, 0.3781449496746063, 0.34657320380210876,
                              6.3935770988464355, 5.4505696296691895, 14.535634994506836];

        for (int i = 0; i < 6; i++) {
          totalMeasures[i] = (totalMeasures[i] * measureStds[i]) + measureMeans[i];
        }

        totalStopwatch.stop();
        final totalSec   = (totalStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(2);
        final infSec     = (totalInferenceMs / 1000.0).toStringAsFixed(2);
        final preSec     = (totalPreprocessMs / 1000.0).toStringAsFixed(2);

        double sanitize(double val) => (val.isNaN || val.isInfinite) ? 0.0 : val;

        replyPort.send({
          'Total_Count':  sanitize(totalCounts[0]),
          'Broken_Count': sanitize(totalCounts[1]),
          'Long_Count':   sanitize(totalCounts[2]),
          'Medium_Count': sanitize(totalCounts[3]),
          'Black_Count':  sanitize(totalCounts[4]),
          'Chalky_Count': sanitize(totalCounts[5]),
          'Red_Count':    sanitize(totalCounts[6]),
          'Yellow_Count': sanitize(totalCounts[7]),
          'Green_Count':  sanitize(totalCounts[8]),
          'Avg_Length':   sanitize(totalMeasures[0]),
          'Avg_Width':    sanitize(totalMeasures[1]),
          'LWR':          sanitize(totalMeasures[2]),
          'Avg_L':        sanitize(totalMeasures[3]),
          'Avg_A':        sanitize(totalMeasures[4]),
          'Avg_B':        sanitize(totalMeasures[5]),
          'Accelerator':  accelerator,
          'Init_Time':    initTime,
          'Pre_Time':     preSec,
          'Inf_Time':     infSec,
          'Total_Time':   totalSec,
        });

      } catch (e, stack) {
        replyPort.send({"error": e.toString()});
      }
    });
  }
}