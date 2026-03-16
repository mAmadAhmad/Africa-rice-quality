import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// SQLite persistence layer for scan history.
///
/// Stores one row per scan with quick-access columns for list views
/// (grade, shape, total_count, broken_pct) and the full inference result
/// serialised as JSON for the detail screen. GPS fields are nullable —
/// rows where the user has not opted in simply store NULL.
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
    final path   = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scans (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path  TEXT,
        timestamp   TEXT,
        grade       TEXT,
        shape       TEXT,
        total_count INTEGER,
        broken_pct  TEXT,
        full_json   TEXT,
        latitude    REAL,
        longitude   REAL,
        has_gps     INTEGER DEFAULT 0
      )
    ''');
  }

  /// Persists a completed scan to the database.
  ///
  /// [processedData] is the merged map from [InferenceService] output and
  /// [RiceLogic] interpretation. The entire map is JSON-encoded into
  /// [full_json] so the detail screen can reconstruct any field without
  /// schema migrations when new output fields are added.
  Future<int> create(Map<String, dynamic> processedData, String imagePath) async {
    final db = await instance.database;

    final data = {
      'image_path':  imagePath,
      'timestamp':   DateTime.now().toIso8601String(),
      'grade':       processedData['milling_grade'],
      'shape':       processedData['grain_shape'],
      'total_count': processedData['total_count'],
      'broken_pct':  processedData['broken_pct'],
      'full_json':   jsonEncode(processedData),
      'latitude':    processedData['latitude'],   // nullable
      'longitude':   processedData['longitude'],  // nullable
      'has_gps':     (processedData['has_gps'] == true) ? 1 : 0,
    };

    return await db.insert('scans', data);
  }

  /// Returns up to 100 scans in reverse-chronological order.
  Future<List<Map<String, dynamic>>> readAllScans() async {
    final db = await instance.database;
    return await db.query('scans', orderBy: 'timestamp DESC', limit: 100);
  }
}