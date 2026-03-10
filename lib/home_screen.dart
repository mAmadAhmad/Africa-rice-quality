import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_info_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = "User";

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? "User";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text("Hello, $_userName!", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Ready to analyze a new sample?", style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 32),
          
          // Guidelines Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("📷 Capture Guidelines", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                  const Divider(),
                  _buildGuideRow(Icons.color_lens, "Use a solid blue background."),
                  _buildGuideRow(Icons.layers_clear, "Spread grains in a single layer (no overlapping)."),
                  _buildGuideRow(Icons.wb_sunny, "Ensure bright, even lighting to avoid shadows."),
                  _buildGuideRow(Icons.center_focus_strong, "Keep the phone steady to avoid blur."),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // App Info Button
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline),
            label: const Text("View App Information & Version"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppInfoScreen()));
            },
          )
        ],
      ),
    );
  }

  Widget _buildGuideRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700], size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}