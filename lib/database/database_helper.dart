import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static const _databaseName = "MyDatabase.db";
  //版本變動後會做哪些處理(新增表格、新增,刪除欄位)
  static const _databaseVersion = 1;

  static const table = 'my_position';


  //Singleton 單例模式，確保一個類別只有一個實例
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    return await _initDatabase();
  }

  Future<bool> checkDatabaseExists() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return File(path).exists();
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    bool databaseExists = await checkDatabaseExists();

    if (!databaseExists) {
      // 创建数据库文件并打开连接
      return await openDatabase(path, version: _databaseVersion,
          onCreate: (Database db, int version) async {
            await db.execute('''
            CREATE TABLE $table (
              id INTEGER NOT NULL,
              time TIMESTAMP NOT NULL PRIMARY KEY,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL)
          ''');
          });
    } else {
      // 打开现有的数据库连接
      Database database = await openDatabase(path, version: _databaseVersion);

      // 检查是否存在 "my_position" 表格
      List<Map<String, dynamic>> tables = await database.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', table],
      );

      if (tables.isEmpty) {
        // 删除现有的数据库文件
        await deleteDatabase(path);

        // 创建新的数据库文件并打开连接
        database = await openDatabase(path, version: _databaseVersion,
            onCreate: (Database db, int version) async {
              await db.execute('''
                CREATE TABLE $table (
                  id INTEGER NOT NULL,
                  time TIMESTAMP NOT NULL PRIMARY KEY,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL)
              ''');
            });
      }
      return database;
    }
  }

  //row傳進來的參數名稱
  //多張表格 (String table,Map<String, dynamic> row)
  Future<int> insert(Map<String, dynamic> row) async {
    Database? db = await instance.database;
    return await db.insert(table, row);
  }

  //尋找全部表格
  Future<List<Map<String, dynamic>>> queryAllRows() async {
    Database? db = await instance.database;
    return await db.query(table);
  }

  //firstIntValue拿出第一個值(回傳很多值)
  Future<int?> queryRowCount() async {
    Database? db = await instance.database;
    return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $table'));
  }

  //id=指定的才做更新(哪張表個,資料，條件式)
  Future<int> update(Map<String, dynamic> row) async {
    Database? db = await instance.database;
    int id = row['id'];
    return await db.update(table, row, where: 'id = ?', whereArgs: [id]);
  }

  //db!表示db變數不為空
  Future<int> delete() async {
    Database? db = await instance.database;
    return await db.delete(table);
  }

  // 新增刪除表格的方法
  Future<void> deleteAllTables() async {
    Database? db = await instance.database;
    List<Map<String, dynamic>> tables = await db.query(
      'sqlite_master',
      where: 'type = ?',
      whereArgs: ['table'],
    );

    for (Map<String, dynamic> table in tables) {
      String tableName = table['name']!;
      await db.execute('DROP TABLE IF EXISTS $tableName');
    }
  }

  Future<void> deleteDatabaseFile() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    await deleteDatabase(path);
  }
}