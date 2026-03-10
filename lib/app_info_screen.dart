import 'package:flutter/material.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Information')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Icon(Icons.verified_user, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            "Rice Quality Analyzer",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Version 1.0.0",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const Divider(height: 48, thickness: 2),
          
          _buildInfoRow("Model Name", "Ultimate Specialist (ConvNeXt-Small)"),
          _buildInfoRow("Model Version", "AfricaRice V4 Quantized (Edge)"),
          _buildInfoRow("Inference Framework", "ONNX Runtime (XNNPACK)"),
          _buildInfoRow("Data Source", "Trained on 4K multi-scale grid patches"),
          
          const Divider(height: 48, thickness: 2),
          
          const Text(
            "Intellectual Property",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            "The underlying machine learning models and dataset properties are co-owned by UNIDO and AfricaRice as per the competition guidelines. This application utilizes open-source languages and tools exclusively.",
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.black87, fontSize: 15)),
        ],
      ),
    );
  }
}