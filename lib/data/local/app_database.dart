import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const fileName = 'guia.db';

  static Future<Database> open({String? path}) {
    return _open(path);
  }

  static Future<Database> _open(String? path) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE places (
            id TEXT PRIMARY KEY,
            year_founded INTEGER,
            year_completed INTEGER,
            tour_available INTEGER,
            related_object_id TEXT,
            celular TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE place_translations (
            place_id TEXT NOT NULL,
            locale TEXT NOT NULL,
            name TEXT,
            name2 TEXT,
            description TEXT,
            crypt_description TEXT,
            location TEXT,
            direccion TEXT,
            opening_hours TEXT,
            architectural_style TEXT,
            historical_notes TEXT,
            entrance_fee TEXT,
            category TEXT,
            PRIMARY KEY (place_id, locale)
          )
        ''');
        await db.execute('''
          CREATE TABLE place_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            path TEXT NOT NULL,
            sort INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE beacons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id TEXT NOT NULL,
            mac TEXT,
            uuid TEXT,
            major INTEGER,
            minor INTEGER,
            rssi_enter INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE recommendations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id TEXT,
            match_title TEXT NOT NULL,
            image_url TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            altitude REAL,
            celular TEXT,
            direccion TEXT,
            year_founded INTEGER,
            year_completed INTEGER,
            tour_available INTEGER,
            related_object_id TEXT,
            entrance_fee TEXT,
            category TEXT,
            architectural_style TEXT,
            historical_notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE recommendation_translations (
            recommendation_id INTEGER NOT NULL,
            locale TEXT NOT NULL,
            title TEXT,
            location TEXT,
            description TEXT,
            opening_hours TEXT,
            PRIMARY KEY (recommendation_id, locale)
          )
        ''');
        await db.execute('''
          CREATE TABLE recommendation_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recommendation_id INTEGER NOT NULL,
            path TEXT NOT NULL,
            sort INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE carousel_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            sort INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE carousel_titles (
            locale TEXT PRIMARY KEY,
            title TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE carousel_paragraphs (
            locale TEXT NOT NULL,
            sort INTEGER NOT NULL,
            paragraph TEXT NOT NULL,
            PRIMARY KEY (locale, sort)
          )
        ''');
        await db.execute('''
          CREATE TABLE contact_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            comment TEXT NOT NULL,
            rating INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }
}
