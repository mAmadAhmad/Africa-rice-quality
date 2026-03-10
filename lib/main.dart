import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'inference_service.dart';
import 'disclaimer_screen.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'export_screen.dart';
import 'profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  InferenceService().init();
  
  final prefs = await SharedPreferences.getInstance();
  final isRegistered = prefs.getBool('is_registered') ?? false;

  runApp(MaterialApp(
    title: 'AfricaRice Quality',
    theme: ThemeData(
      primarySwatch: Colors.green,
      useMaterial3: true,
    ),
    home: isRegistered ? const MainShell() : const DisclaimerScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // The 4 background tabs (Capture is handled by the FAB)
  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const ExportScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      
      // The Protruding Capture Button
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        onPressed: () {
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (_) => const CameraScreen())
          );
        },
        child: const Icon(Icons.camera_alt, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      
      // The Bottom Navigation Bar
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTabIcon(icon: Icons.home, label: "Home", index: 0),
            _buildTabIcon(icon: Icons.history, label: "History", index: 1),
            const SizedBox(width: 48), // Empty space for the FAB
            _buildTabIcon(icon: Icons.share, label: "Export", index: 2),
            _buildTabIcon(icon: Icons.person, label: "Profile", index: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildTabIcon({required IconData icon, required String label, required int index}) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isSelected ? Colors.green : Colors.grey),
          Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.green : Colors.grey)),
        ],
      ),
    );
  }
}