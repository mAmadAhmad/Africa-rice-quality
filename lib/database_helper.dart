import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rice_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE scans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      image_path TEXT,
      timestamp TEXT,
      grade TEXT,
      shape TEXT,
      total_count INTEGER,
      broken_pct TEXT,
      full_json TEXT,
      latitude REAL,
      longitude REAL,
      has_gps INTEGER DEFAULT 0
    )
    ''');
  }

  Future<int> create(Map<String, dynamic> processedData, String imagePath) async {
    final db = await instance.database;
    
    final data = {
      'image_path': imagePath,
      'timestamp': DateTime.now().toIso8601String(),
      'grade': processedData['milling_grade'],
      'shape': processedData['grain_shape'],
      'total_count': processedData['total_count'],
      'broken_pct': processedData['broken_pct'],
      'full_json': jsonEncode(processedData),
      // NEW: Safely map the nullable GPS fields
      'latitude': processedData['latitude'],
      'longitude': processedData['longitude'],
      'has_gps': (processedData['has_gps'] == true) ? 1 : 0, 
    };
    
    return await db.insert('scans', data);
  }

  Future<List<Map<String, dynamic>>> readAllScans() async {
    final db = await instance.database;
    return await db.query('scans', orderBy: 'timestamp DESC', limit: 100);
  }
}