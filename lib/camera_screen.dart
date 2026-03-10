import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'inference_service.dart';
import 'rice_logic.dart';
import 'database_helper.dart';
import 'results_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isAnalyzing = false;
  String? _capturedImagePath;
  String? _pendingImagePath;

  bool _showGuidance = true;
  int _currentTile = 0;
  int _totalTiles = 12;

  // ── NEW: State for Rice Type ──
  String _selectedRiceType = 'White'; 

  // ── GPS ──
  bool _gpsEnabled = false;   
  double? _pendingLat;        
  double? _pendingLon;
  String _gpsStatus = '';     

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadGpsPreference();

    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showGuidance = false);
    });
  }

  Future<void> _loadGpsPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _gpsEnabled = prefs.getBool('enable_gps') ?? false);
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.off);

    if (mounted) setState(() => _isCameraInitialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onTapToFocus(TapUpDetails details, BoxConstraints constraints) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    _controller!.setFocusPoint(offset);
  }

  Future<void> _fetchGpsIfEnabled() async {
    if (!_gpsEnabled) return;

    setState(() => _gpsStatus = 'fetching');

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = 'unavailable');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 4),
      );

      _pendingLat = position.latitude;
      _pendingLon = position.longitude;
      setState(() => _gpsStatus = 'locked');
    } catch (_) {
      _pendingLat = null;
      _pendingLon = null;
      setState(() => _gpsStatus = 'unavailable');
    }
  }

  Future<void> _pickImage() async {
    if (_isAnalyzing) return;
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      await _fetchGpsIfEnabled();
      setState(() => _pendingImagePath = image.path);
    } catch (e) {
      print("❌ Gallery Error: $e");
    }
  }

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized ||
        _controller!.value.isTakingPicture ||
        _isAnalyzing) return;
    try {
      final results = await Future.wait([
        _controller!.takePicture(),
        _fetchGpsIfEnabled().then((_) => null),
      ]);
      final XFile photo = results[0] as XFile;
      setState(() => _pendingImagePath = photo.path);
    } catch (e) {
      print("❌ Camera Error: $e");
    }
  }

  Future<void> _processImage(String imagePath) async {
    final double? lat = _pendingLat;
    final double? lon = _pendingLon;

    setState(() {
      _capturedImagePath = imagePath;
      _isAnalyzing = true;
      _currentTile = 0;
      _gpsStatus = '';
      _pendingLat = null;
      _pendingLon = null;
    });

    try {
      final inferenceService = InferenceService();
      
      // ── CHANGED: Passed _selectedRiceType here ──
      final rawData = await inferenceService.analyzeImage(
        imagePath,
        riceType: _selectedRiceType, 
        onProgress: (current, total) {
          if (mounted) setState(() {
            _currentTile = current;
            _totalTiles = total;
          });
        },
      );

      if (rawData['validation_failed'] == true) {
        if (mounted) _showValidationWarning(rawData['reason']);
        return;
      }

      final processedData = RiceLogic.interpretResults(rawData);

      final Map<String, dynamic> dataToSave = {
        ...rawData,
        ...processedData,
        'latitude':  lat,
        'longitude': lon,
        'has_gps':   lat != null && lon != null,
        'sample_type': _selectedRiceType, // Save type to DB!
      };

      await DatabaseHelper.instance.create(dataToSave, imagePath);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("Analysis Complete ✅"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "🏆 Grade: ${processedData['milling_grade']}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text("📏 Shape: ${processedData['grain_shape']}",
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text("🌾 Class: ${processedData['length_class']}",
                    style: const TextStyle(fontSize: 16)),

                if (_gpsEnabled) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        lat != null ? Icons.location_on : Icons.location_off,
                        size: 16,
                        color: lat != null ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lat != null
                              ? "${lat.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}"
                              : "Location unavailable",
                          style: TextStyle(
                            fontSize: 12,
                            color: lat != null ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  "Scan saved to history successfully.",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultsScreen(
                        data: dataToSave, 
                        imagePath: imagePath,
                      ),
                    ),
                  );
                },
                child: const Text("Detailed Metrics"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _capturedImagePath = null);
                },
                child: const Text("Done"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showValidationWarning(
          "Analysis could not complete.\n\nThe image may be corrupted, or your device may be low on memory.",
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showValidationWarning(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("⚠️ Invalid Image"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _capturedImagePath = null);
            },
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Capture Rice Sample"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_gpsEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: _buildGpsStatusBadge(),
            ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapUp: (details) => _onTapToFocus(details, constraints),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: (_capturedImagePath != null)
                      ? Image.file(File(_capturedImagePath!), fit: BoxFit.contain)
                      : (_pendingImagePath != null)
                          ? Image.file(File(_pendingImagePath!), fit: BoxFit.contain)
                          : CameraPreview(_controller!),
                ),
              );
            },
          ),

          AnimatedOpacity(
            opacity: _showGuidance && !_isAnalyzing && _capturedImagePath == null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGuideRow(Icons.color_lens, Colors.blueAccent, "Use a solid BLUE background"),
                    const SizedBox(height: 6),
                    _buildGuideRow(Icons.layers_clear, Colors.amber, "Spread grains in a SINGLE layer"),
                    const SizedBox(height: 6),
                    _buildGuideRow(Icons.center_focus_strong, Colors.white, "Avoid blur & darkness"),
                  ],
                ),
              ),
            ),
          ),

          if (_isAnalyzing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.green),
                      const SizedBox(height: 24),
                      const Text(
                        "Analyzing Sample...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LinearProgressIndicator(
                        value: _totalTiles == 0 ? null : _currentTile / _totalTiles,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Processing patch $_currentTile of $_totalTiles",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        "Please keep the app open.\nHigh-precision edge ML in progress.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  Widget _buildGpsStatusBadge() {
    switch (_gpsStatus) {
      case 'fetching':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
          ),
          SizedBox(width: 4),
          Text("GPS...", style: TextStyle(fontSize: 12, color: Colors.amber)),
        ]);
      case 'locked':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on, color: Colors.greenAccent, size: 16),
          SizedBox(width: 4),
          Text("GPS ✓", style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
        ]);
      case 'unavailable':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_off, color: Colors.grey, size: 16),
          SizedBox(width: 4),
          Text("No GPS", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]);
      default:
        return const Icon(Icons.location_on, color: Colors.white38, size: 18);
    }
  }

  Widget? _buildFloatingActionButtons() {
    if (_isAnalyzing) return null;

    // PREVIEW MODE — Accept / Retake
    if (_pendingImagePath != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            
            // ── NEW: Rice Type Dropdown Selector ──
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRiceType,
                  dropdownColor: Colors.black87,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.green),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  items: ['Paddy', 'White', 'Brown'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text("$value Rice"),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() => _selectedRiceType = newValue);
                    }
                  },
                ),
              ),
            ),

            if (_gpsEnabled && _gpsStatus.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _gpsStatus == 'locked'
                        ? Colors.green
                        : _gpsStatus == 'fetching'
                            ? Colors.amber
                            : Colors.grey,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _gpsStatus == 'locked'
                          ? Icons.location_on
                          : _gpsStatus == 'fetching'
                              ? Icons.gps_not_fixed
                              : Icons.location_off,
                      size: 14,
                      color: _gpsStatus == 'locked'
                          ? Colors.green
                          : _gpsStatus == 'fetching'
                              ? Colors.amber
                              : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _gpsStatus == 'locked'
                          ? "${_pendingLat?.toStringAsFixed(4)}, ${_pendingLon?.toStringAsFixed(4)}"
                          : _gpsStatus == 'fetching'
                              ? "Getting location..."
                              : "Location unavailable",
                      style: TextStyle(
                        fontSize: 12,
                        color: _gpsStatus == 'locked'
                            ? Colors.green
                            : _gpsStatus == 'fetching'
                                ? Colors.amber
                                : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton.large(
                  heroTag: "retake_btn",
                  onPressed: () => setState(() {
                    _pendingImagePath = null;
                    _pendingLat = null;
                    _pendingLon = null;
                    _gpsStatus = '';
                  }),
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.close, color: Colors.white, size: 40),
                ),
                FloatingActionButton.large(
                  heroTag: "accept_btn",
                  onPressed: () {
                    final path = _pendingImagePath!;
                    setState(() => _pendingImagePath = null);
                    _processImage(path);
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.check, color: Colors.white, size: 40),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // CAMERA MODE — Shoot / Gallery
    if (_capturedImagePath == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 56),
            FloatingActionButton.large(
              heroTag: "take_photo_btn",
              onPressed: _takePicture,
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.camera, color: Colors.green, size: 40),
            ),
            FloatingActionButton(
              heroTag: "pick_gallery_btn",
              onPressed: _pickImage,
              backgroundColor: Colors.black54,
              elevation: 0,
              child: const Icon(Icons.photo_library, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return null;
  }

  Widget _buildGuideRow(IconData icon, Color iconColor, String text) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ],
    );
  }
}