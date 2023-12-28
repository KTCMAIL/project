import 'dart:math';
import 'dart:async';
import 'package:mysql1/mysql1.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thecover/main.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:thecover/notifications.dart';
import 'package:flutter_compass/flutter_compass.dart';

class MysqlManager {
  Timer? _driverDistanceComparisonTimer; //駕駛模式比較位置
  Timer? _userDistanceCompareTimer; //行人模式比較求救距離
  Timer? _uploadTableIdTimer; //支援者上傳位置計時
  Timer? _uploadDistressSignalTimer; //求救中上傳位置
  Timer? _uploadUserPositionTimer; //救援端上傳位置

  static const userIdTable = 'user_id';
  static const accountTable = 'account';
  static const userPositionTable = 'user_position';
  static const distressSignalTable = 'distress_signal';

  // 已處理的id
  Set<int> handledComeIds300 = {}; // 靠近(聲音)
  Set<int> handledComeIds150 = {}; // 靠近(聲音)
  Set<int> comparingId = {}; //正在判斷的id

  // 存放聲音、訊息
  List<String> comeToMe = []; // 靠近(訊息)
  List<String> soundCome = []; // 靠近(聲音方位)
  List<String> soundAllComeText = []; // 靠近(要播放的聲音)

  // 判斷
  List<String> playSound300 = []; // 判斷要不要播聲音(300~150m存放處)
  List<String> playSound150 = []; // 判斷要不要播聲音(<150m存放處)
  List<String> sendCome = []; // 判斷要不要傳靠近通知
  List<String> changeState = []; // 判斷車輛轉換方向
  bool isPlayingSound = false; // 判斷484正在播放聲音

  // 記錄每個 id 的上一次方位
  Map<int, String> previousAzMap = {};

  //駕駛模式
  double currentMyLat = 999;
  double currentMyLon = 999;

  // 行人頁面發求救通知
  int previousCountIn500 = 0;
  int countIn500 = 0;

  //final只能連線一次，所以使用late
  late MySqlConnection conn;

  MysqlManager() {
    initConnection();
  }

  Future<void> initConnection() async {
    conn = await MySqlConnection.connect(ConnectionSettings(
        host: '130.211.255.234',
        port: 3306,
        user: 'root',
        db: 'cloud01',
        password: '123456'
    ));
  }
  void dispose() {
    conn.close();
  }



  //初始頁面 =>確認user_id,account,user_position,distress_signal是否被建立
  Future<void> createTable() async {
    await createTableOrNot(accountTable, '''
      CREATE TABLE $accountTable (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        password VARCHAR(50) NOT NULL
      )
    ''');

    await createTableOrNot(userPositionTable, '''
      CREATE TABLE $userPositionTable (
        id INT NOT NULL,
        time TIMESTAMP NOT NULL,
        lat DECIMAL(15,10) NOT NULL,
        lon DECIMAL(15,10) NOT NULL,
        PRIMARY KEY (id, time)
      )
    ''');

    await createTableOrNot(distressSignalTable, '''
      CREATE TABLE $distressSignalTable (
        id INT NOT NULL PRIMARY KEY,
        time TIMESTAMP NOT NULL,
        lat DECIMAL(15,10) NOT NULL,
        lon DECIMAL(15,10) NOT NULL,
        message VARCHAR(50) NOT NULL
      )
    ''');

    await createTableOrNot(userIdTable, '''
      CREATE TABLE $userIdTable (
        uid INT NOT NULL AUTO_INCREMENT PRIMARY KEY
      )
    ''');
  }

  Future<void> createTableOrNot(String tableName, String query) async {
    var results = await conn.query('''
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = "cloud01" AND table_name = "$tableName"
  ''');

    if (results.first[0] == 0) {
      try {
        await conn.query(query);
        print("Table '$tableName' has been created.");
      } catch (e) {
        print("Error creating table '$tableName': $e");
      }
    } else {
      print("Table '$tableName' already exists.");
    }
  }

  Future<int> insertUserId() async {
    var result = await conn.query(
        'INSERT INTO $userIdTable (uid) VALUES (null)'
    );

    var insertedUid = result.insertId;

    return insertedUid!;
  } //使用者的Uid



  //註冊帳密使用
  Future<void> insertAccount(String username, String password) async {
    var result = await conn.query(
        'INSERT INTO $accountTable (username, password) VALUES (?, ?)',
        [username, password]);
    print('Inserted account row id=${result.insertId}   --- insert account 執行結束---');
  }



  //救援端
  Future<void> insertUserPosition(int id, double lat, double lon) async {
    DateTime now = DateTime.timestamp().add(const Duration(hours: 8));
    var result = await conn.query(
      'INSERT INTO $userPositionTable (id, time, lat, lon) VALUES (?, ?, ?, ?)',
      [id, now, lat, lon],
    );

    if (result.affectedRows == 1) {
      var insertedRow = await conn.query(
          'SELECT * FROM $userPositionTable WHERE id = ?', [id]);

      if (insertedRow.isNotEmpty) {
        print('Inserted => id: $id, Time: $now, lat: $lat, lon: $lon');
      }
    } else {
      print('Failed to insert user position data');
    }
    print('--- insert user position 執行結束---');
  } //this & test

  Future<void> deleteIdUserPositionTable(int id) async {
    await conn.query('''
    DELETE FROM $userPositionTable
    WHERE id = ?
  ''', [id]);
  }//結束任務刪除我的位置

  void startUploadUserPositionTimer(int id) {
    _uploadUserPositionTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) async {
      Position position = await getUserCurrentLocation();

      var countResult = await conn.query(
        'SELECT COUNT(*) FROM $userPositionTable WHERE id = ?',
        [id],
      );
      var count = countResult.first[0];
      await insertUserPosition(id, position.latitude, position.longitude);

      if (count > 2) {
        var oldestResult = await conn.query(
          'SELECT * FROM $userPositionTable WHERE id = ? ORDER BY time ASC LIMIT 1',
          [id],
        );
        var oldestRow = oldestResult.first;
        var oldestId = oldestRow['id'];
        var oldestTime = oldestRow['time'];

        await conn.query(
          'DELETE FROM $userPositionTable WHERE id = ? AND time = ?',
          [oldestId, oldestTime],
        );
      }

      await queryUserPositionTable(); //測試用可刪除
    });
  } //上傳位置、需要test時間

  void stopUploadUserPositionTimer() {
    _uploadUserPositionTimer?.cancel();
  }



  //求救中頁面
  Future<void> createIdTable(int id) async {
    await conn.query('''
        CREATE TABLE table_$id (
          id INT NOT NULL,
          time TIMESTAMP NOT NULL PRIMARY KEY,
          lat DECIMAL(15,10) NOT NULL,
          lon DECIMAL(15,10) NOT NULL)
      ''');
    print('table_$id 已建立');
  } //建立table,讓支援者可以上傳位置

  Future<void> checkIdTable(int id) async {
    var results = await conn.query('''
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = "cloud01" AND table_name = "table_$id"
    ''');

    if (results.first[0] == 0) {
      await conn.query('''
        CREATE TABLE table_$id (
          id INT NOT NULL,
          time TIMESTAMP NOT NULL PRIMARY KEY,
          lat DECIMAL(15,10) NOT NULL,
          lon DECIMAL(15,10) NOT NULL)
      ''');
      print('table_$id 已建立');
    }
  }

  Future<void> deleteUidDistressSignal(int id) async {
    await conn.query('''
    DELETE FROM $distressSignalTable
    WHERE id = ?
  ''', [id]);
  } //求救結束刪除我的位置

  Future<void> deleteUidTable(int id) async {
    final result = await conn.query('''
      SELECT COUNT(*) as count
      FROM information_schema.tables
      WHERE table_schema = "cloud01" AND table_name = "table_$id"
    ''');

    final count = result.first['count'];

    if (count == 1) {
      // 如果表格存在，则执行删除操作
      await conn.query('DROP TABLE table_$id');
      print('表格 table_$id 已成功删除');//測試求救結束後表格是否刪除
      queryDistressSignalTable(); //測試求救結束後訊息是否刪除
    }
  } //求救結束刪除我的資料

  Future<void> querySupportPosition(List<Map<String, dynamic>> positions, int uid) async {
    var results = await conn.query('SELECT DISTINCT id FROM table_$uid');

    for (var row in results) {
      int id = row['id'];
      var recentPositions = await conn.query('''
      SELECT id, time, lat, lon 
      FROM table_$uid 
      WHERE id = ?
      ORDER BY time DESC
      LIMIT 1''', [id]);

      for (var row in recentPositions) {
        positions.add({
          'id': row['id'],
          'time': row['time'],
          'lat': row['lat'],
          'lon': row['lon'],
        });
      }
    }
  } //查詢支援者位置

  void startUploadDistressSignalTimer(int id) {
    createIdTable(id);
    _uploadDistressSignalTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) async {//尚未確認要多久、正式測試需更改位置
      DateTime now = DateTime.timestamp().add(const Duration(hours: 8));
      Position position = await getUserCurrentLocation();

      await checkIdTable(id);

      var countResult = await conn.query(
        'SELECT COUNT(*) FROM $distressSignalTable WHERE id = ?',
        [id],
      );
      var count = countResult.first[0];

      if (count > 0) {
        await conn.query(
          'UPDATE $distressSignalTable SET time = ?, lat = ?, lon = ? WHERE id = ?',
          [now, position.latitude, position.longitude, id], //實際使用：position.latitude, position.longitude
          // 測試用：24.219500, 120.712197(冠廷家附近)、24.147979, 120.700558(Tina)、25.044359, 121.532968
        );
      }
      queryDistressSignalTable(); //測試用可刪除
      queryCertainIdTable(id); //測試用可刪除
    });
  } //上傳位置、需要test時間

  void stopUploadDistressSignalTimer() {
    _uploadDistressSignalTimer?.cancel();
  }



  //救援行動頁面
  Future<List<double>> queryIdDistressSignalTable(int id) async {
    double lat = 0.0;
    double lon = 0.0;
    var results = await conn.query('SELECT lat, lon FROM $distressSignalTable WHERE id = ?', [id]);

    for (var row in results) {
      lat = row[0];
      lon = row[1];
    }
    return [lat, lon];
  } //找我選擇支援的sos位置

  Future<void> deleteCertainIdTablePosition(int ids,int id) async {
    await conn.query('''
    DELETE FROM table_$ids
    WHERE id = ?
  ''', [id]);
  } //在支援的sos table刪除我的位置

  Future<void> insertCertainIdTable(int otherUid, int uid, double lat, double lon) async {
    DateTime now = DateTime.timestamp().add(const Duration(hours: 8));
    var result = await conn.query(
      'INSERT INTO table_$otherUid (id, time, lat, lon) VALUES (?, ?, ?, ?)',
      [uid, now, lat, lon],
    );

    if (result.affectedRows == 1) {
      var insertedRow = await conn.query(
          'SELECT * FROM table_$otherUid WHERE id = ?', [uid]);

      if (insertedRow.isNotEmpty) {
        print('Inserted => id: $uid, Time: $now, lat: $lat, lon: $lon');
      }
    } else {
      print('Failed to insert IdTable data');
    }
    print('--- insert IdTable 執行結束---');
  }

  void startUploadTableIdTimer(context,int otherUid,int uid) {
    _uploadTableIdTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      DateTime now = DateTime.timestamp().add(const Duration(hours: 8));
      Position position = await getUserCurrentLocation();

      var results = await conn.query('''
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = "cloud01" AND table_name = "table_$otherUid"
    ''');

      if (results.first[0] == 0) {
        stopUploadTableIdTimer(); // 停止 timer
        Fluttertoast.showToast(
          msg: '支援已結束',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 3,
          backgroundColor: Colors.black26.withOpacity(0.6),
          textColor: Colors.white,
        );
        Navigator.pop(context);
        Navigator.pop(context);
        Navigator.pop(context);
      }//判斷table存在與否

      var countResult = await conn.query('SELECT COUNT(*) FROM table_$otherUid WHERE id = ?', [uid]);
      var count = countResult.first[0];

      if (count > 0) {
        await conn.query('UPDATE table_$otherUid SET time = ?, lat = ?, lon = ? WHERE id = ?',
          [now, position.latitude, position.longitude, uid],
        );
        await queryCertainIdTable(otherUid); //測試用可刪除
      }
    });
  } // 確定為2秒

  void stopUploadTableIdTimer() {
    _uploadTableIdTimer?.cancel();
  }



  // 很多地方用到
  Future<Position> getUserCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return position;
  } //我現在位置

  Future<double?> getMyAzimuth() async {
    try {
      CompassEvent? event = await FlutterCompass.events?.first;
      double? azimuth = event?.heading;
      print('azimuth:$azimuth');
      return azimuth;
    } catch (e) {
      print('Error getting azimuth: $e');
      return 999;
    }
  }  //獲取方位角(Azimuth angle，縮寫為Az)

  Future<List<Map<String, dynamic>>> queryRecentMysqlPositions(int id, int queryValue) async {
    var results;

    switch (queryValue) {
      case 1:
        results = await conn.query('''
        SELECT id, time, lat, lon
        FROM $userPositionTable
        WHERE id = ?
        ORDER BY time DESC
        LIMIT ?
      ''', [id, 1]);

        break;
      case 2:
        results = await conn.query('''
        SELECT id, time, lat, lon
        FROM $userPositionTable
        WHERE id = ?
        ORDER BY time DESC
        LIMIT ?
      ''', [id, 2]);

        break;
      default:

    }

    List<Map<String, dynamic>> positions = [];
    for (var row in results) {
      positions.add({
        'id': row['id'],
        'time': row['time'],
        'lat': row['lat'],
        'lon': row['lon'],
      });
    }

    return positions;
  } //查詢user_position近幾筆位置



  //行人模式
  void notificationTo0() {
    countIn500 = 0;
    previousCountIn500 = 0;
  } // 進入行人將控制通知歸零

  void startUserDistanceComparisonTimer(BuildContext context) {
    _userDistanceCompareTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      Position position = await getUserCurrentLocation();
      double myLat = position.latitude;
      double myLon = position.longitude;

      previousCountIn500 = countIn500;
      var results = await conn.query('SELECT * FROM $distressSignalTable');
      countIn500 = 0; // 計算 < 500m 的數量
      notificationBarState.newSupportList.clear();

      for (var row in results) {
        int id = row['id'];
        double lat = row['lat'];
        double lon = row['lon'];
        var message = row['message'];

        double distance = calculateDistance(myLat, myLon, lat, lon) * 1000; // 轉換成公尺
        int distanceInMeters = distance.toInt(); // 轉換為整數
        if (distance > 500) {
          print('距離：$distanceInMeters 公尺 太遠了!');
        } else {
          countIn500++;
          SupportItem item = SupportItem(id, message, distanceInMeters);
          notificationBarState.newSupportList.add(item);
          print('$message');
          print('現在距離：$distanceInMeters 公尺');
        }
      }

      // 發通知
      if (countIn500 != previousCountIn500 && countIn500 > 0) {
        Notify.initialize();
        Notify.showBigTextNotification(title: '求救訊號', body: '附近有$countIn500筆');
      }

    });
  } //偵測500公尺內是否有求救訊號

  void stopUserDistanceComparisonTimer() {
    _userDistanceCompareTimer?.cancel();
  }
  void stopBackUserDistanceComparisonTimer() {
    _userDistanceCompareTimer?.cancel();
  }

  Future<void> backStartUserDistanceComparisonTimer(double myLat, double myLon) async{
    //_backUserDistanceCompareTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      print('in');
      //Position position = await getUserCurrentLocation();
      //double myLat = position.latitude;
      //double myLon = position.longitude;

      previousCountIn500 = countIn500;
      print('countIn500:$countIn500、previousCountIn500:$previousCountIn500');
      var results = await conn.query('SELECT * FROM $distressSignalTable');
      countIn500 = 0; // 計算 < 500m 的數量
      //notificationBarState.newSupportList.clear();
      for (var row in results) {
        print('in for');
        int id = row['id'];
        double lat = row['lat'];
        double lon = row['lon'];
        var message = row['message'];

        double distance = calculateDistance(myLat, myLon, lat, lon) * 1000; // 轉換成公尺
        int distanceInMeters = distance.toInt(); // 轉換為整數
        if (distance > 500) {
          print('距離：$distanceInMeters 公尺 太遠了!');
        } else {
          countIn500++;
          print('$message');
          print('現在距離：$distanceInMeters 公尺');
        }
      }

      if (countIn500 != previousCountIn500 && countIn500 > 0) {
        // 發通知
        Notify.initialize();
        Notify.showBigTextNotification(title: '求救訊號', body: '附近有$countIn500筆');
      }
      print('out');
    //});
  } //背景



  // 駕駛模式
  Future<List<Map<String, dynamic>>> queryMysqlPositionList() async {
    String icon = '';
    List<Map<String, dynamic>> mysqlPositionIn350 = [];
    Position myPosition = await getUserCurrentLocation();
    var results = await conn.query('SELECT DISTINCT id FROM $userPositionTable');

    for (var row in results) {
      int id = row['id'];
      List<Map<String, dynamic>> mysqlPositions = await queryRecentMysqlPositions(id,2);

      if (mysqlPositions.length >= 2 ) {
        var endMysqlPosition = mysqlPositions[0]; //最新位置(終點)
        var startMysqlPosition = mysqlPositions[1]; //次新位置(起點)
        double endDistance = calculateDistance(myPosition.latitude, myPosition.longitude, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000;

        if (endDistance < 300) {
          double mysqlBearing = calculateBearing(startMysqlPosition['lat'], startMysqlPosition['lon'], endMysqlPosition['lat'], endMysqlPosition['lon']);
          double? azimuth = await getMyAzimuth();
          double bearingDifference = (azimuth! - mysqlBearing + 360) % 360; // azimuth、mysqlBearing範圍都是-180~180

          if (azimuth != 999){
            if (bearingDifference > 337.5 && bearingDifference < 360 || bearingDifference > 0 && bearingDifference < 22.5) {
              icon = 'behind';
            } else if (bearingDifference > 22.5 && bearingDifference < 67.5) {
              icon = 'rightBehind';
            } else if (bearingDifference > 67.5 && bearingDifference < 112.5) {
              icon = 'right';
            } else if (bearingDifference > 112.5 && bearingDifference < 157.5) {
              icon = 'rightFront';
            } else if (bearingDifference > 157.5 && bearingDifference < 202.5) {
              icon = 'front';
            } else if (bearingDifference > 202.5 && bearingDifference < 247.5) {
              icon = 'leftFront';
            } else if (bearingDifference > 247.5 && bearingDifference < 292.5) {
              icon = 'left';
            } else if (bearingDifference > 292.5 && bearingDifference < 337.5) {
              icon = 'leftBehind';
            } //基準：我的方位

            Map<String, dynamic> idLocationIcon = {
              'id': id,
              'lat': endMysqlPosition['lat'],
              'lon': endMysqlPosition['lon'],
              'icon': icon,
            };

            mysqlPositionIn350.add(idLocationIcon);
          } else {
            print('$id無法獲取AZ');
          }
        } else {
          print('$id>350m');
        }
      } else {
        print('$id<2筆經緯度');
      }
    }
    return mysqlPositionIn350;
  } //判斷救護車在地圖上的八方位

  void stopDriverDistanceComparisonTimer() {
    _driverDistanceComparisonTimer?.cancel();
  }

  void startDriverDistanceComparisonTimer() {
    _driverDistanceComparisonTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) async{
      print('isPlayingSound：$isPlayingSound、comparingId.isEmpty：$comparingId');
      if(!isPlayingSound && comparingId.isEmpty){
        var results = await conn.query('SELECT DISTINCT id FROM $userPositionTable');

        List<int> distinctIds = [];
        for (var row in results) {
          distinctIds.add(row['id']);
        }

        comeToMe.clear(); // 清空方位信息列表
        soundCome.clear(); // 清空靠近聲音列表

        // 對每個不同的ID查詢最近的經緯度
        for (int id in distinctIds) {
          comparingId.add(id);
          await distanceComparison(id);
        }

        print('sendCome：$sendCome、changeState：$changeState');
        print('playSound150：$playSound150、playSound300：$playSound300、changeState：$changeState');

        Notify.initialize();
        // 通知靠近訊息
        if (sendCome.isNotEmpty || changeState.isNotEmpty) {
          String locations = comeToMe.join(' 和 '); // 將方位訊息連接為字串
          String notificationText = '救援車輛從 $locations 靠近';
          await Notify.showBigTextNotification(title: '附近有救援車輛', body: notificationText); // 發送通知
        }

        // 播靠近聲音
        if(playSound150.isNotEmpty || playSound300.isNotEmpty || changeState.isNotEmpty){
          isPlayingSound = true;
          Notify notify = Notify();
          soundAllComeText.clear();
          soundAllComeText.add('sound/carFrom.mp3'); // 靠近聲音(救援車輛從)
          soundAllComeText.addAll(soundCome);
          soundAllComeText.add('sound/come.mp3'); // 靠近聲音
          await notify.playSound(soundAllComeText);
          print('撥放靠近聲音');
        }

        isPlayingSound = false;

        soundCome.clear(); // 清空靠近聲音列表

        sendCome.clear(); // 清空控制傳靠近訊息
        playSound300.clear(); // 清空控制播靠近聲音
        playSound150.clear(); // 清空控制播靠近聲音
        changeState.clear(); // 清空控制變換狀態

        comparingId.clear(); //判斷結束所有判斷了沒
        print('end');
      }
    });
  }   //搜索救援車輛所有不同的id

  Future<void> distanceComparison(int id) async {
    Position position = await getUserCurrentLocation();
    currentMyLat = position.latitude;
    currentMyLon = position.longitude; //真正要用-我的現在位置

    List<Map<String, dynamic>> mysqlPositions = await queryRecentMysqlPositions(id,1);

    var endMysqlPosition = mysqlPositions[0]; // 最新位置(終點)

    double distance = calculateDistance(currentMyLat, currentMyLon, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000; // 轉換成公尺
    int distanceInMeters = distance.toInt(); // 轉換為整數

    if (distance > 300) {
      print('車輛id：$id $distanceInMeters m 太遠了!  --- distanceComparison 执行结束---');
    } else{
      await distanceFarOrNear(id);
    }
  }  //查救援車輛id最近一筆+判斷和我現在距離是350m

  Future<void> distanceFarOrNear(int id) async {
    List<Map<String, dynamic>> mysqlPositions = await queryRecentMysqlPositions(id,2);
    var endMysqlPosition = mysqlPositions[0]; //最新位置(終點)
    var startMysqlPosition = mysqlPositions[1]; //次新位置(起點)

    double endDistance = calculateDistance(currentMyLat, currentMyLon, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000; // 轉換成公尺
    double startDistance = calculateDistance(currentMyLat, currentMyLon, startMysqlPosition['lat'], startMysqlPosition['lon']) * 1000; // 轉換成公尺

    if (endDistance > startDistance) {
      print('車輛id：$id => 已駛離  --- distanceFarOrNear 执行结束---');
      handledComeIds300.remove(id);
      handledComeIds150.remove(id);
    } else {
      await compareBearing(id);
    }
  }  //查救援車輛id最近兩筆+判斷和我現在距離(假設我現在位置ing)

  Future<void> compareBearing(int id) async {
    String azDistance = '';
    String? previousAz = previousAzMap[id]; // 取得上一次救護車方向

    List<Map<String, dynamic>> mysqlPositions = await queryRecentMysqlPositions(id, 2);

    // 需再增加我的位置判斷不到的條件
    if (mysqlPositions.length >= 2) {
      var endMysqlPosition = mysqlPositions[0]; // 最新位置(終點)
      var startMysqlPosition = mysqlPositions[1]; // 次新位置(起點)
      double? azimuth = await getMyAzimuth();

      double mysqlBearing = calculateBearing(startMysqlPosition['lat'], startMysqlPosition['lon'], endMysqlPosition['lat'], endMysqlPosition['lon']);
      double bearingDifference = (azimuth! - mysqlBearing + 360) % 360; // azimuth、mysqlBearing範圍都是-180~180

      if (azimuth != 999){
        int resultLR = await distanceMyFrontOrBehind(currentMyLat, currentMyLon, id, azimuth+90); // 1=左邊(後面)、2=右邊(前面)
        int resultBF = await distanceMyFrontOrBehind(currentMyLat, currentMyLon, id, azimuth); // 1=後面、2=前面

        if (bearingDifference > 337.5 && bearingDifference < 360 || bearingDifference > 0 && bearingDifference < 22.5) { //後方
          print('車輛id：$id在 => 後方');
          azDistance = '後方';
          soundCome.add('sound/behind.mp3'); // 靠近聲音

        } else if (bearingDifference > 22.5 && bearingDifference < 67.5) { //右後方
          if (resultLR == 2) { //我的右邊
            print('車輛id：$id在 => 右後方');
            azDistance = '後方';
            soundCome.add('sound/behind.mp3');
          } else { //我的左邊
            //print('車輛id：$id在 => 右後方(左)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          }

        } else if (bearingDifference > 67.5 && bearingDifference < 112.5) { //右方
          if (resultBF == 2) { //我的前面
            print('車輛id：$id在 => 右方(前面)');
            azDistance = '右方';
            soundCome.add('sound/right.mp3');
          } else { //我的後面
            //print('車輛id：$id在 => 右方(後面)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          }

        } else if (bearingDifference > 112.5 && bearingDifference < 157.5) { //右前方
          if (resultLR == 2) {
            if (resultBF == 2) { //我的右前
              print('車輛id：$id在 => 右前方');
              azDistance = '前方';
              soundCome.add('sound/front.mp3');
            } else { //我的右後
              //print('車輛id：$id在 => 右前方(右後)已駛離');
              handledComeIds300.remove(id);
              handledComeIds150.remove(id);
            }
          } else { //我的左邊
            //print('車輛id：$id在 => 右前方(左)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          }

        } else if (bearingDifference > 157.5 && bearingDifference < 202.5) { //前方
          print('車輛id：$id在 => 前方');
          azDistance = '前方';
          soundCome.add('sound/front.mp3');

        } else if (bearingDifference > 202.5 && bearingDifference < 247.5) { //左前方
          if (resultLR == 2) { //我的右邊
            //print('車輛id：$id在 => 左前方(右)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          } else {
            if (resultBF == 2) { //我的左前
              print('車輛id：$id在 => 左前方');
              azDistance = '前方';
              soundCome.add('sound/front.mp3');
            } else { //我的左後
              //print('車輛id：$id在 => 左前方(左後)已駛離');
              handledComeIds300.remove(id);
              handledComeIds150.remove(id);
            }
          }

        } else if (bearingDifference > 247.5 && bearingDifference < 292.5) { //左方
          if (resultBF == 2) { //我的前面
            print('車輛id：$id在 => 左方');
            azDistance = '左方';
            soundCome.add('sound/left.mp3');
          } else { //我的後面
            //print('車輛id：$id在 => 左方(後面)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          }
        } else if (bearingDifference > 292.5 && bearingDifference < 337.5) { //左後方
          if (resultLR == 2) { //我的右邊
            //print('車輛id：$id在 => 左後方(右)已駛離');
            handledComeIds300.remove(id);
            handledComeIds150.remove(id);
          } else { //我的左邊
            print('車輛id：$id在 => 左後方');
            azDistance = '後方';
            soundCome.add('sound/behind.mp3');
          }
        }

        if (azDistance !=''){
          comeToMe.add(azDistance); // 訊息

          double distance = calculateDistance(currentMyLat, currentMyLon, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000; // 轉換成公尺
          if (distance > 150 && distance <300){
            if (!handledComeIds300.contains(id)) { //判斷有沒有播過300m
              sendCome.add('true'); // 控制訊息傳送
              playSound300.add('true'); // 控制聲音播報
              handledComeIds300.add(id);
            }
          } else if (distance <150) {
            if (!handledComeIds150.contains(id)) { //判斷有沒有播過150m
              sendCome.add('true'); // 控制訊息傳送
              playSound150.add('true'); // 控制聲音靠近播報
              handledComeIds150.add(id);
            }
          }
        }

        // 狀態改變就通知訊息和聲音
        if (previousAz != azDistance){
          changeState.add('true'); // 控制訊息聲音靠近播報
          print('change');
        }
        previousAzMap[id] = azDistance; //更新id先前位置

        int AZ = azimuth.toInt();
        int MysqlBearing = mysqlBearing.toInt();
        int BearingDifference = bearingDifference.toInt();
        print('我的方位：$AZ,救援車輛$id方位：$MysqlBearing=$BearingDifference  --- compareBearing 执行结束---');

        print('soundCome：$soundCome');

      } else {
        print('無法獲取AZ');
      }
    } else {
      print('無足夠的位置數據來判斷行進方向  --- compareBearing 执行结束---');
    }
  }  //查救援車輛id最近2筆+判斷和我2筆距離判斷方位(假設我的位置ing)

  Future<int> distanceMyFrontOrBehind(double currentMyLat,double currentMyLon, int id,double azimuth) async {
    List previousMyPosition = await inferPreviousLocation(currentMyLat, currentMyLon, azimuth); //獲取先前位置的经纬度
    double previousMyLat = previousMyPosition[0];
    double previousMyLon = previousMyPosition[1];

    List<Map<String, dynamic>> mysqlPositions = await queryRecentMysqlPositions(id,1);
    var endMysqlPosition = mysqlPositions[0]; //最新位置(終點)

    double endDistance = calculateDistance(currentMyLat, currentMyLon, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000; // 轉換成公尺
    double startDistance = calculateDistance(previousMyLat, previousMyLon, endMysqlPosition['lat'], endMysqlPosition['lon']) * 1000; // 轉換成公尺

    if (endDistance > startDistance) {
      print('救援車輛$id => 我的後面  --- distanceMyFrontOrBehind 执行结束---');
      return 1;
    } else {
      print('救援車輛$id => 我的前面  --- distanceMyFrontOrBehind 执行结束---');
      return 2;
    }
  }  //查救援車輛id最近1筆+判斷和我2筆距離



  //計算公式
  Future<List<double>> inferPreviousLocation(double currentMyLat,double currentMyLon, double azimuth) async{
    double previousMyLat = 999;
    double previousMyLon = 999;
    // 计算先前位置的經緯度
    double bearing = (azimuth + 180) % 360;  // 我的方位角
    double bearingRad = pi * bearing / 180.0;  // 将方位角轉換為弧度
    double distance = 15 / 1000.0;  // 轉換為公里，距離我10m

    double earthRadius = 6371.0;  // 地球半徑（单位：千米）

    double currentLatRad = pi * currentMyLat / 180.0;  // 當前緯度（弧度）
    double currentLonRad = pi * currentMyLon / 180.0;  // 當前經度（弧度）

    double newLatRad = asin(
        sin(currentLatRad) * cos(distance / earthRadius) +
            cos(currentLatRad) * sin(distance / earthRadius) * cos(bearingRad)
    );

    double newLonRad = currentLonRad + atan2(
        sin(bearingRad) * sin(distance / earthRadius) * cos(currentLatRad),
        cos(distance / earthRadius) - sin(currentLatRad) * sin(newLatRad)
    );

    // 将推断得到的经纬度转换为度数
    previousMyLat = newLatRad * 180.0 / pi;
    previousMyLon = newLonRad * 180.0 / pi;

    print('現在我的位置：纬度：$currentMyLat, 经度：$currentMyLon');
    print('推断先前位置：纬度：$previousMyLat, 经度：$previousMyLon');

    // 將計算結果存入 List 並返回
    List<double> previousLocation = [previousMyLat, previousMyLon];
    return previousLocation;
  }  // 計算我的先前位置(15m)
  double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    // 將經緯度轉換為弧度
    double lat1Rad = pi * lat1 / 180;
    double lon1Rad = pi * lon1 / 180;
    double lat2Rad = pi * lat2 / 180;
    double lon2Rad = pi * lon2 / 180;

    // 計算方位角
    double y = sin(lon2Rad - lon1Rad) * cos(lat2Rad);
    double x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(lon2Rad - lon1Rad);
    double bearingRad = atan2(y, x);

    // 將弧度轉換為角度
    double bearingDeg = bearingRad * 180 / pi;

    // 將角度轉換為0到360度的範圍
    return (bearingDeg + 360) % 360;
  }  // 計算方位角 1起始點,2是終點
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    double dLat = radians(lat2 - lat1);
    double dLon = radians(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(radians(lat1)) * cos(radians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    return distance;
  }  // 大圓距離公式
  double radians(double degrees) {
    return degrees * pi / 180;
  }



  //test
  Future<void> insertDistressSignal(int id, double lat, double lon, String message) async {
    DateTime now = DateTime.timestamp().add(const Duration(hours: 8));
    var result = await conn.query(
      'INSERT INTO $distressSignalTable (id, time, lat, lon, message) VALUES (?, ?, ?, ?, ?)',
      [id, now, lat, lon, message],
    );

    //判斷是否成功插入
    if (result.affectedRows == 1) {
      var insertedRow = await conn.query(
          'SELECT * FROM $distressSignalTable WHERE id = ?', [id]);

      if (insertedRow.isNotEmpty) {
        var row = insertedRow.first;
        print('Inserted => id: ${row[0]}, Time: $now, lat: ${row[2]}, lon: ${row[3]}, 求救訊息: ${row[4]}');
      }
    } else {
      print('Failed to insert Distress Signal data');
    }
    print('--- insert Distress Signal 執行結束---');
  } //test
  Future<void> queryCertainIdTable(int id) async {
    var results = await conn.query('SELECT * FROM table_$id' );
    for (var row in results) {
      print('id: ${row[0]}, Time: ${row[1]}, lat: ${row[2]}, lon: ${row[3]}');
    }
    print('--- query CertainIdTable  執行結束---');
  } //test
  Future<void> queryAccountTable() async {
    var results = await conn.query('SELECT * FROM $accountTable' );
    for (var row in results) {
      print('id: ${row[0]}, username: ${row[1]}, password: ${row[2]}');
    }
    print('--- query AccountTable  執行結束---');
  } //test
  Future<void> queryUserPositionTable() async {
    var results = await conn.query('SELECT * FROM $userPositionTable' );
    for (var row in results) {
      print('id: ${row[0]}, Time: ${row[1]}, lat: ${row[2]}, lon: ${row[3]}');
    }
    print('--- query UserPositionTable  執行結束---');
  } //test
  Future<void> queryDistressSignalTable() async {
    var results = await conn.query('SELECT * FROM $distressSignalTable' );
    for (var row in results) {
      print('id: ${row[0]}, Time: ${row[1]}, lat: ${row[2]}, lon: ${row[3]}, 求救訊息: ${row[4]}');
    }
    print('--- query distressSignalTable  執行結束---');
  } //test
  Future<void> deleteDataAccountTable() async {
    await conn.query('DELETE FROM $accountTable');
    print('--- deleteData AccountTable 執行結束---');
  } //test
  Future<void> deleteDataUserPositionTable() async {
    await conn.query('DELETE FROM $userPositionTable');
    print('--- deleteData UserPositionTable 執行結束---');
  } //test
  Future<void> deleteDistressSignalTable() async {
    await conn.query('DELETE FROM $distressSignalTable');
    print('--- deleteData distressSignalTable 執行結束---');
  } //test

  }
