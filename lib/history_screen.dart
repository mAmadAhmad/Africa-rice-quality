import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'results_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _scanHistory;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  void _refreshHistory() {
    setState(() => _scanHistory = DatabaseHelper.instance.readAllScans());
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    return "${date.day}/${date.month}/${date.year} "
           "at ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan History (Last 100)')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _scanHistory,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text("No scans yet. Take a photo!",
                  style: TextStyle(fontSize: 18)),
            );
          }

          final scans = snapshot.data!;

          return ListView.builder(
            itemCount: scans.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final scan = scans[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    // Decode the full JSON blob stored at write time so the
                    // ResultsScreen receives every inference field without
                    // requiring additional database queries.
                    final Map<String, dynamic> fullData =
                        jsonDecode(scan['full_json']);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResultsScreen(
                          data: fullData,
                          imagePath: scan['image_path'],
                        ),
                      ),
                    );
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(scan['image_path']),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        // Gracefully handle images deleted from device storage.
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 60),
                      ),
                    ),
                    title: Text(
                      "${scan['grade']} | ${scan['shape']}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                            "Total: ${scan['total_count']} "
                            "(${scan['broken_pct']}% Broken)"),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(scan['timestamp']),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}