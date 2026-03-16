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

          _buildInfoRow(
            "Model Architecture",
            "ConvNeXt-Small with 9 MultiScale CSR Density Heads",
          ),
          _buildInfoRow(
            "Training Technique",
            "Two-phase gradual unfreezing — backbone frozen for 7 epochs, "
            "then fully fine-tuned at 10× reduced learning rate to prevent "
            "catastrophic forgetting of ImageNet features",
          ),
          _buildInfoRow(
            "Model Version",
            "AfricaRice V4 — 3×4 Tile Grid, INT8 Quantized (55.6 MB)",
          ),
          _buildInfoRow(
            "Inference Framework",
            "ONNX Runtime Mobile with XNNPACK Multi-Threaded CPU acceleration",
          ),
          _buildInfoRow(
            "Inference Speed",
            "~32 seconds per image on mid-range Android (Snapdragon 720G)",
          ),
          _buildInfoRow(
            "Data Policy",
            "All scan data is stored locally on this device. Nothing is uploaded.",
          ),

          const Divider(height: 48, thickness: 2),

          const Text(
            "Intellectual Property",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            "The underlying machine learning models and dataset are co-owned by "
            "UNIDO and AfricaRice as per the AfricaRice Quality Challenge guidelines. "
            "This application is built exclusively with open-source frameworks and "
            "is intended for non-commercial field assessment use only.",
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
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4)),
        ],
      ),
    );
  }
}