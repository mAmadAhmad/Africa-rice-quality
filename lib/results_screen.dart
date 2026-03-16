import 'dart:io';
import 'package:flutter/material.dart';

/// Displays the full inference output for a single scan.
/// Receives [data] — the merged map from [InferenceService] and [RiceLogic] —
/// and [imagePath] pointing to the captured sample image.
/// Used both directly after a scan and when revisiting history (via JSON decode).
class ResultsScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String imagePath;

  const ResultsScreen({
    super.key,
    required this.data,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Detailed Analysis")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 24),

          // Primary quality grade — prominently displayed at the top
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  data['milling_grade'] ?? data['grade'] ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // GPS section — only rendered when location data was captured
          if (data['latitude'] != null && data['longitude'] != null) ...[
            _buildSectionTitle("Location Data"),
            _buildDataRow("Coordinates",
                "${data['latitude']}, ${data['longitude']}"),
            const SizedBox(height: 16),
          ],

          _buildSectionTitle("Grain Count & Structure"),
          _buildDataRow("Total Grains", "${data['total_count']}"),
          if (data['broken_count'] != null)
            _buildDataRow("Broken Grains",
                "${data['broken_count']} (${data['broken_pct']}%)"),
          if (data['long_count']   != null)
            _buildDataRow("Long Grains",   "${data['long_count']}"),
          if (data['medium_count'] != null)
            _buildDataRow("Medium Grains", "${data['medium_count']}"),
          const SizedBox(height: 16),

          _buildSectionTitle("Shape & Dimensions"),
          _buildDataRow("Shape Profile",
              data['grain_shape'] ?? data['shape']),
          if (data['avg_length']   != null)
            _buildDataRow("Avg Length",   "${data['avg_length']} mm"),
          if (data['avg_width']    != null)
            _buildDataRow("Avg Width",    "${data['avg_width']} mm"),
          if (data['lwr']          != null)
            _buildDataRow("L/W Ratio",    "${data['lwr']}"),
          if (data['length_class'] != null)
            _buildDataRow("Length Class", data['length_class']),
          const SizedBox(height: 16),

          // Defect section reads directly from raw ML counts (Chalky_Count etc.)
          // rather than derived percentages, to show exact grain numbers.
          if (data['Chalky_Count'] != null) ...[
            _buildSectionTitle("Defects & Discoloration"),
            _buildDataRow("Chalky Grains",
                "${(data['Chalky_Count'] as num).toInt()}"),
            _buildDataRow("Black (Damaged)",
                "${(data['Black_Count'] as num).toInt()}"),
            _buildDataRow("Red Strips",
                "${(data['Red_Count'] as num).toInt()}"),
            _buildDataRow("Green (Immature)",
                "${(data['Green_Count'] as num).toInt()}"),
            _buildDataRow("Yellow (Fermented)",
                "${(data['Yellow_Count'] as num).toInt()}"),
            const SizedBox(height: 16),
          ],

          if (data['cielab_l'] != null) ...[
            _buildSectionTitle("Colour Profile (CIELAB)"),
            _buildDataRow("Lightness (L*)",  "${data['cielab_l']}"),
            _buildDataRow("Green-Red (a*)",  "${data['cielab_a']}"),
            _buildDataRow("Blue-Yellow (b*)", "${data['cielab_b']}"),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
      child: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 16, color: Colors.black87)),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}