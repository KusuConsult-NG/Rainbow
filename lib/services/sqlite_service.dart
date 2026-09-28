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
      // v2: lat/lng became nullable. An SOS raised with no GPS fix must be
      // queued WITHOUT coordinates rather than with invented ones — see
      // E2E_AUDIT_REPORT.md C-5.
      //
      // v3: reported_by. The queue did not store WHO raised the report, so
      // `buildOfflineSyncPayload` could not carry it and **every alert synced
      // from the offline queue reached HQ with no reporter**. A dispatcher could
      // not call them back, the reporter could not see their own report under
      // RLS, and HQ's offline-channel dedup — which scopes by reporter — could
      // never match it. Found while wiring the offline channels, which is the
      // first thing that needed both ends of this to line up.
      version: 3,
      onUpgrade: _upgrade,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_id TEXT UNIQUE NOT NULL,
            type TEXT NOT NULL,
            description TEXT,
            lat REAL,
            lng REAL,
            priority TEXT NOT NULL,
            is_anonymous INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            reported_by TEXT
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

  /// v1 -> v2: drop NOT NULL from offline_queue.lat/lng.
  ///
  /// SQLite has no `ALTER COLUMN`, so the table is rebuilt and rows copied.
  /// Queued alerts are unsent emergencies — they must survive the upgrade.
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE offline_queue RENAME TO offline_queue_v1');
        await txn.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_id TEXT UNIQUE NOT NULL,
            type TEXT NOT NULL,
            description TEXT,
            lat REAL,
            lng REAL,
            priority TEXT NOT NULL,
            is_anonymous INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
        await txn.execute('''
          INSERT INTO offline_queue
            (id, local_id, type, description, lat, lng, priority,
             is_anonymous, created_at, sync_status)
          SELECT id, local_id, type, description, lat, lng, priority,
                 is_anonymous, created_at, sync_status
          FROM offline_queue_v1
        ''');
        await txn.execute('DROP TABLE offline_queue_v1');
      });
    }
    if (oldVersion < 3) {
      // ADD COLUMN rather than a rebuild: SQLite supports it, it is nullable, and
      // queued alerts are unsent emergencies that must survive the upgrade
      // untouched. Rows written before v3 keep a null reporter, which is the
      // truth about them — they were queued by a build that never recorded it.
      await db.execute('ALTER TABLE offline_queue ADD COLUMN reported_by TEXT');
    }
  }

  Future<int> enqueueAlert({
    required String localId,
    required String type,
    required String description,
    required double? lat,
    required double? lng,
    required String priority,
    required bool isAnonymous,
    required String createdAt,
    String syncStatus = 'PENDING',
    String? reportedBy,
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
        // Null for an anonymous report, and only then. Anything else means the
        // report reaches HQ unattributed.
        'reported_by': isAnonymous ? null : reportedBy,
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
