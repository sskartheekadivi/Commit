import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'database.g.dart';

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  // NEW: Ability to archive categories
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('Habit')
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get type => text()();
  IntColumn get color => integer().nullable()();
  TextColumn get notificationText => text().nullable()();
  IntColumn get reminderHour => integer().nullable()();
  IntColumn get reminderMinute => integer().nullable()();
  TextColumn get reminderDays => text().nullable()();
  RealColumn get targetValue => real().nullable()();
  TextColumn get unit => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
}

@DataClassName('Log')
class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId => integer().references(Habits, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get value => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>>? get uniqueKeys => [{habitId, date}];
}

@DataClassName('EnumOption')
class EnumOptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId => integer().references(Habits, #id)();
  TextColumn get value => text()();
  IntColumn get color => integer()();
}

@DriftDatabase(tables: [Habits, Logs, EnumOptions, Categories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 9; // BUMPED TO 9

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // ... Previous migrations (1-8) ...
      if (from < 2) await m.createTable(enumOptions);
      if (from < 3) await m.addColumn(habits, habits.color);
      if (from < 4) {
        await m.drop(logs);
        await m.createTable(logs);
      }
      if (from < 5) await m.addColumn(habits, habits.notificationText);
      if (from < 6) await m.addColumn(habits, habits.orderIndex);
      if (from < 7) {
        await m.addColumn(habits, habits.reminderHour);
        await m.addColumn(habits, habits.reminderMinute);
        await m.addColumn(habits, habits.reminderDays);
      }
      if (from < 8) {
        await m.createTable(categories);
        await m.addColumn(habits, habits.categoryId);
      }
      
      // NEW MIGRATION FOR v9
      if (from < 9) {
        // 1. Add archived column
        await m.addColumn(categories, categories.archived);
        
        // 2. DATA MIGRATION: Convert "Uncategorized" to "General"
        // We do this manually to ensure data integrity
        final generalId = await into(categories).insert(
          CategoriesCompanion.insert(name: 'General', orderIndex: const Value(0))
        );
        
        // Move all NULL category habits to "General"
        await (update(habits)..where((h) => h.categoryId.isNull()))
            .write(HabitsCompanion(categoryId: Value(generalId)));
      }
    },
    beforeOpen: (details) async {
      // Safety Check: Ensure a 'General' category always exists if we have orphaned habits
      // This handles fresh installs or weird states
      if (details.wasCreated) {
         await into(categories).insert(
            CategoriesCompanion.insert(name: 'General', orderIndex: const Value(0))
         );
      }
    }
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}
