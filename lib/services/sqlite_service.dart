import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final sqliteServiceProvider = Provider<SqliteService>((ref) {
  return SqliteService();
});

class SqliteService {
  SqliteService();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final pathString = join(dbPath, 'rainbow_offline.db');

    return openDatabase(
      pathString,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_id TEXT UNIQUE NOT NULL,
            type TEXT NOT NULL,
            description TEXT,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            priority TEXT NOT NULL,
            is_anonymous INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE offline_media (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_alert_id TEXT NOT NULL,
            local_file_path TEXT NOT NULL,
            remote_storage_path TEXT,
            upload_status TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> enqueueAlert({
    required String localId,
    required String type,
    required String description,
    required double lat,
    required double lng,
    required String priority,
    required bool isAnonymous,
    required String createdAt,
    String syncStatus = 'PENDING',
  }) async {
    final db = await database;
    return db.insert(
      'offline_queue',
      {
        'local_id': localId,
        'type': type,
        'description': description,
        'lat': lat,
        'lng': lng,
        'priority': priority,
        'is_anonymous': isAnonymous ? 1 : 0,
        'created_at': createdAt,
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingAlerts() async {
    final db = await database;
    return db.query(
      'offline_queue',
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: ['PENDING', 'FAILED'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteAlert(String localId) async {
    final db = await database;
    await db.delete(
      'offline_queue',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateSyncStatus(String localId, String status) async {
    final db = await database;
    await db.update(
      'offline_queue',
      {'sync_status': status},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> enqueueMedia({
    required String localAlertId,
    required String localFilePath,
    String uploadStatus = 'PENDING',
  }) async {
    final db = await database;
    return db.insert(
      'offline_media',
      {
        'local_alert_id': localAlertId,
        'local_file_path': localFilePath,
        'upload_status': uploadStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingMedia(String localAlertId) async {
    final db = await database;
    return db.query(
      'offline_media',
      where: 'local_alert_id = ? AND upload_status = ?',
      whereArgs: [localAlertId, 'PENDING'],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPendingMedia() async {
    final db = await database;
    return db.query(
      'offline_media',
      where: 'upload_status = ?',
      whereArgs: ['PENDING'],
    );
  }

  Future<void> updateMediaStatus(int id, String status, {String? remoteStoragePath}) async {
    final db = await database;
    final data = <String, dynamic>{'upload_status': status};
    if (remoteStoragePath != null) {
      data['remote_storage_path'] = remoteStoragePath;
    }
    await db.update(
      'offline_media',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remapAlertId(String oldId, String newId) async {
    final db = await database;
    await db.update(
      'offline_media',
      {'local_alert_id': newId},
      where: 'local_alert_id = ?',
      whereArgs: [oldId],
    );
  }

  Future<void> deleteMedia(int id) async {
    final db = await database;
    await db.delete(
      'offline_media',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAlertSynced(String localId) async {
    final db = await database;
    await db.update(
      'offline_queue',
      {'sync_status': 'SYNCED'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }
}
