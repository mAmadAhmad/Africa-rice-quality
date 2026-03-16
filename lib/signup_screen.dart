import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'main.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _orgController  = TextEditingController();
  bool _enableGps = false;

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Name is required",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text.trim());
    await prefs.setString('user_role', _roleController.text.trim());
    await prefs.setString('user_org',  _orgController.text.trim());
    await prefs.setBool('enable_gps',  _enableGps);
    // Mark registration complete so the app routes to MainShell on next launch.
    await prefs.setBool('is_registered', true);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  // Request the location permission at the moment the toggle is switched on
  // rather than at app launch, so the permission dialog appears in context.
  Future<void> _toggleGps(bool value) async {
    if (value) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("GPS permission denied. Cannot enable location."),
          ));
        }
        return;
      }
    }
    setState(() => _enableGps = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            "Welcome! Please set up your profile.",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: 'Name / Username *',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _roleController,
            decoration: const InputDecoration(
                labelText: 'Role (Optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _orgController,
            decoration: const InputDecoration(
                labelText: 'Organisation (Optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text("Save GPS Location"),
            subtitle: const Text("Opt-in to attach coordinates to scans."),
            value: _enableGps,
            activeColor: Colors.green,
            onChanged: _toggleGps,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: _saveProfile,
            child: const Text('Save & Continue',
                style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}