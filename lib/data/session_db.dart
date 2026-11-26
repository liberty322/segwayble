/// SQLite database for ride sessions, telemetry, and saved devices.
library;

import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'ride_session.dart';
import 'saved_device.dart';

/// Singleton database for ride session storage.
class SessionDatabase {
  static SessionDatabase? _instance;
  static Database? _db;

  SessionDatabase._();

  factory SessionDatabase() => _instance ??= SessionDatabase._();

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/sessions.db';
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            max_ble_speed REAL NOT NULL DEFAULT 0,
            max_gps_speed REAL NOT NULL DEFAULT 0,
            avg_ble_speed REAL NOT NULL DEFAULT 0,
            distance REAL NOT NULL DEFAULT 0,
            accel_0_45_time REAL,
            duration INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE telemetry_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            ble_speed REAL NOT NULL DEFAULT 0,
            gps_speed REAL,
            power INTEGER NOT NULL DEFAULT 0,
            battery INTEGER NOT NULL DEFAULT 0,
            lat REAL,
            lng REAL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_telemetry_session ON telemetry_points(session_id)');
        await _createSavedDevicesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSavedDevicesTable(db);
        }
        if (oldVersion < 3) {
          // Add auth+sn columns for session reuse (skip PRE_COMM on reconnect)
          await db.execute(
              'ALTER TABLE saved_devices ADD COLUMN auth TEXT');
          await db.execute(
              'ALTER TABLE saved_devices ADD COLUMN sn TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE saved_devices ADD COLUMN counter INTEGER');
        }
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE saved_devices ADD COLUMN command_ident TEXT');
        }
      },
    );
  }

  static Future<void> _createSavedDevicesTable(Database db) async {
    await db.execute('''
      CREATE TABLE saved_devices (
        mac TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        last_connected INTEGER NOT NULL,
        serial_number TEXT,
        password TEXT,
        auth TEXT,
        sn TEXT,
        counter INTEGER,
        command_ident TEXT
      )
    ''');
  }

  // -- Sessions --

  Future<int> insertSession(RideSession session) async {
    final db = await database;
    return db.insert('sessions', session.toMap());
  }

  Future<void> updateSession(RideSession session) async {
    final db = await database;
    await db.update('sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<RideSession?> getSession(int id) async {
    final db = await database;
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return RideSession.fromMap(rows.first);
  }

  Future<List<RideSession>> getAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'start_time DESC');
    return rows.map(RideSession.fromMap).toList();
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  // -- Telemetry --

  Future<void> insertTelemetry(TelemetryPoint point) async {
    final db = await database;
    await db.insert('telemetry_points', point.toMap());
  }

  Future<List<TelemetryPoint>> getTelemetry(int sessionId) async {
    final db = await database;
    final rows = await db.query('telemetry_points',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC');
    return rows.map(TelemetryPoint.fromMap).toList();
  }

  // -- Saved Devices --

  Future<void> upsertSavedDevice(SavedDevice device) async {
    final db = await database;
    await db.insert('saved_devices', device.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SavedDevice>> getSavedDevices() async {
    final db = await database;
    final rows =
        await db.query('saved_devices', orderBy: 'last_connected DESC');
    return rows.map(SavedDevice.fromMap).toList();
  }

  Future<void> deleteSavedDevice(String mac) async {
    final db = await database;
    await db.delete('saved_devices', where: 'mac = ?', whereArgs: [mac]);
  }

  Future<void> updateDeviceCounter(String mac, int counter) async {
    final db = await database;
    await db.update('saved_devices', {'counter': counter},
        where: 'mac = ?', whereArgs: [mac]);
  }

  Future<Uint8List?> getDevicePassword(String mac) async {
    final saved = await getSavedDevice(mac);
    return saved?.password;
  }

  Future<SavedDevice?> getSavedDevice(String mac) async {
    final db = await database;
    final rows = await db.query('saved_devices',
        where: 'mac = ?', whereArgs: [mac]);
    if (rows.isEmpty) return null;
    return SavedDevice.fromMap(rows.first);
  }
}
