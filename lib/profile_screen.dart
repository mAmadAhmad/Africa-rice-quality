import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _orgController = TextEditingController();
  bool _enableGps = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_name') ?? '';
      _roleController.text = prefs.getString('user_role') ?? '';
      _orgController.text = prefs.getString('user_org') ?? '';
      _enableGps = prefs.getBool('enable_gps') ?? false; // LOAD GPS STATE!
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required"), backgroundColor: Colors.red));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text.trim());
    await prefs.setString('user_role', _roleController.text.trim());
    await prefs.setString('user_org', _orgController.text.trim());
    await prefs.setBool('enable_gps', _enableGps); // SAVE GPS STATE!

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully!"), backgroundColor: Colors.green));
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _toggleGps(bool value) async {
    if (value) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("GPS Permission Denied")));
        return;
      }
    }
    setState(() => _enableGps = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Icon(Icons.account_circle, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name / Username *', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        TextField(controller: _roleController, decoration: const InputDecoration(labelText: 'Role (Optional)', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        TextField(controller: _orgController, decoration: const InputDecoration(labelText: 'Organisation (Optional)', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: const Text("Save GPS Location"),
          subtitle: const Text("Attach coordinates to history."),
          value: _enableGps,
          activeColor: Colors.green,
          onChanged: _toggleGps,
        ),
        
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.green, foregroundColor: Colors.white),
          onPressed: _saveProfile,
          child: const Text('Save Changes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}