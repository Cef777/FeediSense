import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // PROPERLY DEFINED METHOD: This was missing the signature previously
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('feedisense.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, 
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            temp REAL,
            ph REAL,
            doLevel REAL,
            timestamp TEXT,
            mode TEXT,
            status TEXT,
            reason TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            level TEXT,
            message TEXT,
            timestamp TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE feed_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            grams INTEGER,
            temp REAL,
            ph REAL,
            doLevel REAL,
            timestamp TEXT,
            mode TEXT,
            status TEXT,
            reason TEXT
          )
        ''');
        await _createSchedulesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE feed_events ADD COLUMN mode TEXT DEFAULT 'Unknown'");
          await db.execute("ALTER TABLE feed_events ADD COLUMN status TEXT DEFAULT 'Success'");
          await db.execute("ALTER TABLE feed_events ADD COLUMN reason TEXT DEFAULT 'None'");
        }
      }
    );
  }

  Future _createSchedulesTable(Database db) async {
    await db.execute('''
    CREATE TABLE schedules (
      id INTEGER PRIMARY KEY,
      time TEXT,
      grams TEXT
    )
    ''');

    // Initialize 4 empty sessions
    for (int i = 0; i < 4; i++) {
      await db.insert('schedules', {'id': i, 'time': null, 'grams': ''});
    }
  }

  // --- Schedule Persistence Methods ---
  Future<List<Map<String, dynamic>>> fetchSchedules() async {
    final db = await instance.database;
    return await db.query('schedules', orderBy: 'id ASC');
  }

  Future<void> updateSchedule(int id, String? time, String grams) async {
    final db = await instance.database;
    await db.update(
      'schedules',
      {'time': time, 'grams': grams},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Existing Methods ---
  Future<void> insertReading(SensorReading reading) async {
    final db = await instance.database;
    await db.insert('history', {
      'temp': reading.temp,
      'ph': reading.ph,
      'doLevel': reading.doLevel,
      'timestamp': reading.timestamp.toIso8601String(),
    });
  }

  Future<void> insertNotification(AppNotification notification) async {
    final db = await instance.database;
    await db.insert('notifications', {
      'level': notification.level,
      'message': notification.message,
      'timestamp': notification.timestamp.toIso8601String(),
    });
  }

  Future<void> insertFeedEvent(FeedEvent event) async {
    final db = await instance.database;
    await db.insert('feed_events', {
      'grams': event.grams,
      'temp': event.temp,
      'ph': event.ph,
      'doLevel': event.doLevel,
      'timestamp': event.timestamp.toIso8601String(),
    });
  }

  Future<List<SensorReading>> fetchHistory() async {
    final db = await instance.database;
    final result = await db.query('history', orderBy: 'timestamp ASC');
    return result
        .map((json) => SensorReading(
              temp: json['temp'] as double,
              ph: json['ph'] as double,
              doLevel: json['doLevel'] as double,
              timestamp: DateTime.parse(json['timestamp'] as String),
            ))
        .toList();
  }

  Future<List<AppNotification>> fetchNotifications() async {
    final db = await instance.database;
    final result = await db.query('notifications', orderBy: 'timestamp ASC');
    return result
        .map((json) => AppNotification(
              level: json['level'] as String,
              message: json['message'] as String,
              timestamp: DateTime.parse(json['timestamp'] as String),
            ))
        .toList();
  }

  Future<List<FeedEvent>> fetchFeedEvents() async {
    final db = await instance.database;
    final result = await db.query('feed_events', orderBy: 'timestamp ASC');
    return result
        .map((json) => FeedEvent(
              grams: json['grams'] as int,
              temp: json['temp'] as double,
              ph: json['ph'] as double,
              doLevel: json['doLevel'] as double,
              timestamp: DateTime.parse(json['timestamp'] as String),
              mode: json['mode'] as String? ?? 'Unknown',
              status: json['status'] as String? ?? 'Success',
              reason: json['reason'] as String? ?? 'None',
            ))
        .toList();
  }

  Future<void> clearNotifications() async {
    final db = await instance.database;
    await db.delete('notifications');
  }
}