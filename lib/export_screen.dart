import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_helper.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;

  Future<void> _exportData() async {
    setState(() => _isExporting = true);

    try {
      final scans = await DatabaseHelper.instance.readAllScans();

      if (scans.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No scans to export.")),
          );
        }
        return;
      }

      final csvData = StringBuffer();

      // CSV header — 21 columns matching the row builder below.
      // Lat/Lng are left blank when GPS was unavailable or not opted in.
      csvData.writeln(
        "Scan_ID,Timestamp,Lat,Lng,Milling_Grade,Grain_Shape,"
        "Total_Count,Broken_Count,Long_Count,Medium_Count,Black_Count,"
        "Chalky_Count,Red_Count,Yellow_Count,Green_Count,"
        "Avg_Length_mm,Avg_Width_mm,LWR,Avg_L,Avg_a,Avg_b",
      );

      for (final scan in scans) {
        final int    id        = scan['id'];
        final String timestamp = scan['timestamp'] ?? '';
        final double? lat      = scan['latitude'];
        final double? lng      = scan['longitude'];

        // Full inference result is stored as JSON — decode to access all fields.
        final Map<String, dynamic> details =
            jsonDecode(scan['full_json'] ?? '{}');

        final latStr = lat != null ? lat.toStringAsFixed(6) : '';
        final lngStr = lng != null ? lng.toStringAsFixed(6) : '';

        int    getInt(String key)   => (details[key] as num?)?.toInt()           ?? 0;
        String getFloat(String key) => (details[key] as num?)?.toStringAsFixed(2) ?? '0.00';

        csvData.writeln(
          "$id,$timestamp,$latStr,$lngStr,${scan['grade']},${scan['shape']},"
          "${getInt('Total_Count')},${getInt('Broken_Count')},${getInt('Long_Count')},"
          "${getInt('Medium_Count')},${getInt('Black_Count')},${getInt('Chalky_Count')},"
          "${getInt('Red_Count')},${getInt('Yellow_Count')},${getInt('Green_Count')},"
          "${getFloat('Avg_Length')},${getFloat('Avg_Width')},${getFloat('LWR')},"
          "${getFloat('Avg_L')},${getFloat('Avg_A')},${getFloat('Avg_B')}",
        );
      }

      // Write to the system temp directory and trigger the native share sheet.
      // The file persists only for the duration of the share action.
      final tempDir    = await getTemporaryDirectory();
      final csvFile    = File("${tempDir.path}/AfricaRice_Detailed_Export.csv");
      await csvFile.writeAsString(csvData.toString());

      await Share.shareXFiles(
        [XFile(csvFile.path)],
        subject: "AfricaRice Quality Detailed Data Export",
        text: "Attached is the latest AfricaRice Quality Assessment export, "
              "including all detailed metrics and GPS coordinates.",
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.import_export, size: 100, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                "Export Scan History",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                "Generate a detailed CSV file of all your scans, including GPS "
                "coordinates, to share via email.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              _isExporting
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon:  const Icon(Icons.share),
                      label: const Text("Export as CSV",
                          style: TextStyle(fontSize: 18)),
                      onPressed: _exportData,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}