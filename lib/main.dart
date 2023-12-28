import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:thecover/notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thecover/mysql_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:thecover/mapbackground/aed_data.dart';


int uid = 0;


void main() {
  WidgetsFlutterBinding.ensureInitialized(); // 確保WidgetsFlutterBinding已經被初始化
  runApp(MaterialApp(
    initialRoute: '/',
    routes: {
      '/': (context) => const Myapp(),
      '/UserMap': (context) => const UserMap(usertitle: '用戶端-行人模式'),
      '/notificationBar': (context) => const notificationBar(notificationBartitle: '通知欄'),
      '/RescueOperation': (context) => RescueOperation(rescueOperationtitle: '正在進行救援行動',supportItem: SupportItem(50, '求救信息', 100),),
      '/SendSave': (context) => const SendSave(sendtitle: '發出求救'),
      '/WaitForSave': (context) => const WaitForSave(WaitFortitle: '求救中'),
      '/LoginPage': (context) => const LoginPage(logintitle: '登入系統'),
      '/RegistrationPage': (context) => const RegistrationPage(RegistrationPagetitle: '註冊頁面'),
      '/SaveMap': (context) => const SaveMap(savetitle: '救援端-一般模式'),
    },
    debugShowCheckedModeBanner: false,
  ));
  Notify.initialize();
}

class Myapp extends StatefulWidget {
  const Myapp({Key? key}) : super(key: key);

  @override
  State<Myapp> createState() => _MyappState();

}

class _MyappState extends State<Myapp>{
  late MysqlManager mysqlManager;

  @override
  void initState()  {
    super.initState();
    initstep();
    _getCurrentLocation(); // 取得目前位置
  }//進入頁面時的動作

  void _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // 位置服務未啟用，導航到設置中啟用位置服務
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('沒開定位'),
            content: Text('請開定位'),
            actions: [
              TextButton(
                child: Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      } else {
        // 使用者拒絕了位置權限，可以顯示一個提示對話框解釋原因並引導使用者到設置中啟用權限
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('沒給存取權'),
            content: Text('請給存取權'),
            actions: [
              TextButton(
                child: Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } else if (permission == LocationPermission.deniedForever) {
      // 使用者永久拒絕了位置權限，需要引導用戶到設置中啟用位置權限
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('沒給存取權'),
          content: Text('請給存取權'),
          actions: [
            TextButton(
              child: Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } else {
      // 使用者給予了位置權限
    }
  }//有設權限

  void initstep() async {
    mysqlManager = MysqlManager();
    await mysqlManager.initConnection(); // 初始化數據庫連接
    await mysqlManager.createTable();
    int insertedUid = await mysqlManager.insertUserId();
    print('插入的 uid 值為: $insertedUid');
    uid = insertedUid;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '緊急公務車避讓系統',
      home: Scaffold(
        appBar: AppBar(
          centerTitle: true,  //標題置中
          title: const Text('緊急公務車避讓系統', style: TextStyle(fontSize: 24)),
        ),
        body: Center(  //架構放置中心位置
          child: Column(  //行的形式往下排
            children: <Widget>[
              const SizedBox(height: 40),
              const Text('登入系統', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const UserMap(usertitle: '用戶端-行人模式',)),);
                },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200 , 100)
                ),
                child: const Text('用戶端', style: TextStyle(fontSize: 24)),
              ),//button按下後的功能及button上顯示的文字
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LoginPage(logintitle: '登入系統',)),);
                },
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200 , 100)
                ),
                child: const Text('救援端', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SendSave(sendtitle: '求救',)),);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // Background color
                    minimumSize: const Size(200 , 100)
                ),
                child: const Text('求救', style: TextStyle(fontSize: 24),),
              ),
            ],  //設一個列表
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class UserMap extends StatefulWidget {
  final String usertitle;

  const UserMap({Key? key, required this.usertitle}) : super(key: key);

  @override
  State<UserMap> createState() => _UserMapState();
}

class _UserMapState extends State<UserMap> with WidgetsBindingObserver {
  late MysqlManager mysqlManager;
  Set<Marker> markers = {};
  Set<Marker> currentMarkers = {}; // 存儲當前的 Marker
  Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _initialCameraPosition; // 將類型更改為可為空的 CameraPosition?
  late Timer _uploadMapCarTimer;
  bool isAEDButtonPressed = false;

  String _title = '用戶端-行人模式';

  late Position currentPosition;
  double userHeading = 0;
  double _previousHeading = 0.0; // 新增變數來保存上一次的方位角
  bool _userMoveMap = false;

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          const SizedBox(width: 5),
          ElevatedButton(
            onPressed: () async {
              mysqlManager.stopUserDistanceComparisonTimer();//判斷求救訊號
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SendSave(sendtitle: '發出求救')),
              ).then((result) => {
                mysqlManager.notificationTo0(),
                mysqlManager.startUserDistanceComparisonTimer(context),
                if (_title == '用戶端-駕駛模式') {
                  mysqlManager.initConnection(),
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, // Background color
            ),
            child: const Text('求救', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => _toggleTitle(),
            child: const Text('切換模式', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: _showMultipleMarkers,
            child: Text(isAEDButtonPressed ? 'Hide AED' : 'Show AED', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }//設定底部

  void initState()  {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mysqlManager = MysqlManager();
    mysqlManager.initConnection();
    mysqlManager.startUserDistanceComparisonTimer(context);
    mysqlManager.notificationTo0(); // 求救通知儲存值歸零
    _getCurrentLocation(); // 取得目前位置
    startUploadMapCarTimer();
  }//進入頁面時的動作

  void startUploadMapCarTimer(){
    _uploadMapCarTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if(_title == '用戶端-駕駛模式') {
        List<Map<String, dynamic>> mysqlPosition = [];
        mysqlPosition = await mysqlManager.queryMysqlPositionList();
        print(mysqlPosition);

        setState(() {
          currentMarkers = {}; // 先將 markers 清空
        });

        if (mysqlPosition.isNotEmpty) {
          _createCustomMarkers(mysqlPosition);
          print('更新救護車圖案');
        } else {
          setState(() {
            markers = currentMarkers; // 清空marker
          });
        }
      }else{
        _uploadMapCarTimer.cancel();//駕駛模式更新救護車圖標的計時器(行人模式取消timer5)
      }
    });
  }

  @override
  void dispose() {
    //mysqlManager.stopDriverDistanceComparisonTimer();//stopTimer2
    mysqlManager.stopUserDistanceComparisonTimer(); // stopTimer3
    _uploadMapCarTimer.cancel();//駕駛模式更新救護車圖標的計時器
    mysqlManager.dispose(); // 關閉數據庫連接
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }//離開頁面時的動作


  @override
  Widget build(BuildContext context) {
    if (_initialCameraPosition == null) {
      // 目前相機位置尚未初始化，可以顯示一個 Loading
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_title),
        actions: <Widget>[
          if (_title == '用戶端-行人模式')
            IconButton(
                icon: const Icon(Icons.notifications), // 鈴鐺
                onPressed: () {
                  //mysqlManager.stopDriverDistanceComparisonTimer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const notificationBar(
                            notificationBartitle: '通知欄')),
                  ).then((result) {
                    mysqlManager.notificationTo0();
                    notificationBarState.refreshSupportList(); // 刷新通知
                    if (_title == '用戶端-駕駛模式') {
                      mysqlManager.initConnection();
                    }
                  });
                }
            )
        ],
      ),
      body: SafeArea(
        child: GoogleMap(
          markers: markers.union(markers), // 将显示所有标记和自定义标记
          initialCameraPosition: _initialCameraPosition ??
              CameraPosition(target: LatLng(25.042587, 121.532946), zoom: 16, bearing: userHeading),
          onCameraMoveStarted: () { //用戶正在拖動地圖
            setState(() {
              _userMoveMap = true;
            });
          },
          onCameraIdle: () { //用戶停止拖動地圖
            setState(() {
              _userMoveMap = false;
            });
          },
          mapType: MapType.normal,
          myLocationEnabled: true,
          compassEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
          },
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }//介面本身

  void _toggleTitle() {
    setState(() {
      if (_title == '用戶端-行人模式') {
        _title = '用戶端-駕駛模式';
        mysqlManager.queryUserPositionTable();
        startUploadMapCarTimer();
      } else {
        _title = '用戶端-行人模式';
        mysqlManager.notificationTo0();
        _uploadMapCarTimer.cancel();//駕駛模式更新救護車圖標的計時器
        markers.clear();
        if(isAEDButtonPressed == true) {
          markers.addAll(getMarkers());
        }
      }
    });
  }//觸發條件

  // 救護車圖標marker
  Future<void> _createCustomMarkers(List<Map<String, dynamic>> positions) async {
    final Uint8List carIconBehind = await _getBytesFromAsset('assets/image/ambulanceBehind.png');
    final Uint8List carIconFront = await _getBytesFromAsset('assets/image/ambulanceFront.png');
    final Uint8List carIconLeft = await _getBytesFromAsset('assets/image/ambulanceLeft.png');
    final Uint8List carIconLeftBehind = await _getBytesFromAsset('assets/image/ambulanceLeftBehind.png');
    final Uint8List carIconLeftFront = await _getBytesFromAsset('assets/image/ambulanceLeftFront.png');
    final Uint8List carIconRight = await _getBytesFromAsset('assets/image/ambulanceRight.png');
    final Uint8List carIconRightBehind = await _getBytesFromAsset('assets/image/ambulanceRightBehind.png');
    final Uint8List carIconRightFront = await _getBytesFromAsset('assets/image/ambulanceRightFront.png');

    for (var position in positions) {
      final int id = position['id'];
      final double lat = position['lat'];
      final double lon = position['lon'];
      final String selectedIcon = position['icon'];
      final MarkerId markerId = MarkerId('device_marker_$id');
      print('經緯度:$lat,$lon,ID值:$id');

      BitmapDescriptor carIcon; // 宣告 carIcon 變數

      if (selectedIcon == 'behind') {
        carIcon = BitmapDescriptor.fromBytes(carIconBehind);
      } else if (selectedIcon == 'front') {
        carIcon = BitmapDescriptor.fromBytes(carIconFront);
      } else if (selectedIcon == 'left') {
        carIcon = BitmapDescriptor.fromBytes(carIconLeft);
      } else if (selectedIcon == 'leftBehind') {
        carIcon = BitmapDescriptor.fromBytes(carIconLeftBehind);
      } else if (selectedIcon == 'leftFront') {
        carIcon = BitmapDescriptor.fromBytes(carIconLeftFront);
      } else if (selectedIcon == 'right') {
        carIcon = BitmapDescriptor.fromBytes(carIconRight);
      } else if (selectedIcon == 'rightBehind') {
        carIcon = BitmapDescriptor.fromBytes(carIconRightBehind);
      } else if (selectedIcon == 'rightFront') {
        carIcon = BitmapDescriptor.fromBytes(carIconRightFront);
      } else {
        carIcon = BitmapDescriptor.defaultMarker;
      }

      Marker? existingMarker;
      // 確認是否已經存在相同的 Marker 於地圖上
      for (final marker in markers) {
        if (marker.markerId == markerId) {
          existingMarker = marker;
          break;
        }
      }

      if (existingMarker != null) {
        // 更新現有的 Marker 的 position 和 icon 屬性
        currentMarkers.remove(existingMarker);
        currentMarkers.add(existingMarker.copyWith(positionParam: LatLng(lat, lon), iconParam: carIcon));
      } else {
        // 創建新的圖標，並將其加入 markers
        final Marker newMarker = Marker(
          markerId: markerId,
          position: LatLng(lat, lon),
          icon: carIcon,
          anchor: const Offset(0.5, 1),
        );
        currentMarkers.add(newMarker);
      }

      // 使用 setState 將 _currentMarkers 設置為新的值，以更新地圖上的 Marker
      setState(() {
        //markers = currentMarkers;
        if (_title == '用戶端-駕駛模式') {
          markers = currentMarkers;
        }
      });
    }
  }

  void _getCurrentLocation() async {
    // 使用者給予了位置權限
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _initialCameraPosition = CameraPosition(
        target: LatLng(position.latitude, position.longitude),
        zoom: 16,
      );
    });

    Geolocator.getPositionStream().listen((Position currentLocation) async {
      print('檢查變化&更新當前用戶位置');
      // 檢查方位角是否有變化
      double? azimuth = await mysqlManager.getMyAzimuth();
      double az = (azimuth! + 360) % 360;
      if (azimuth != _previousHeading ) {
        print('方位角變化');
        // 方位角有變化，需要轉動地圖為當前的方位
        _previousHeading = az;
        _updateMapHeading(az);
      }
    });
  }

  void _updateMapHeading(double azimuth) async{
    Position position = await Geolocator.getCurrentPosition();
    // 轉動地圖為當前的方位
    if (!_userMoveMap) { //用戶正在拖動地圖
      _controller.future.then((controller) {
        controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 16,
          bearing: azimuth,
        )));
        print('azimuth：$azimuth、地圖轉轉');
      });
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path) async {
    final ByteData data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  } //創建圖像的地方

  Future<void> _showMultipleMarkers() async {
    setState(() {
      if (isAEDButtonPressed) {
        // 如果 isAEDButtonPressed為true，清除所有標記
        markers.clear();
        isAEDButtonPressed = false;
      } else {
        // 如果 isAEDButtonPressed為false，加上標記
        markers.addAll(getMarkers());
        isAEDButtonPressed = true;
      }
    });
  }

}//用戶端介面

class SupportManager {
  List<SupportItem> supportList = [];

}//管理一組支援項(supportList列表儲存SupportItem)
class SupportItem {
  int ids;
  String message;
  int distanceInMeters;

  SupportItem(this.ids, this.message, this.distanceInMeters);

  @override
  int get hashCode => ids.hashCode;//定義hashCode，兩個對象一樣，hashCode一樣，但hashCode一樣，兩個對象不一定一樣

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SupportItem && runtimeType == other.runtimeType && ids == other.ids;//檢查兩個對象的類型和ids是否相同

  @override
  String toString() {
    return '求救內容: $message, 與自身距離: $distanceInMeters 公尺, $ids';
  }
}//支援項的屬性

class notificationBar extends StatefulWidget {
  final String notificationBartitle;
  const notificationBar({Key? key, required this.notificationBartitle}) : super(key: key);

  @override
  State<notificationBar> createState() => notificationBarState();
}

class notificationBarState extends State<notificationBar> {
  String _title = '通知欄';
  late MysqlManager mysqlManager = MysqlManager();
  SupportManager supportManager = SupportManager();
  static List<SupportItem> newSupportList = [];
  SupportItem? selectedSupportItem;
  late Timer _uploadListTimer;

  @override
  void initState() {
    super.initState();
    _title = widget.notificationBartitle;
    _uploadListTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      setState(() {
        supportManager.supportList = newSupportList.toSet().toList(); // 將 newSupportList 的值賦值給 supportManager.supportList
        print(newSupportList);
        print(supportManager.supportList);
      });
    });
  }

  @override
  void dispose() {
    _uploadListTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_title),
        leading: null,
      ),
      body: ListView.builder(
        itemCount: supportManager.supportList.length,
        itemBuilder: (context, index) {
          SupportItem item = supportManager.supportList[index];
          return ListTile(
            leading: const Icon(Icons.sos_rounded, color: Colors.red),
            title: Text(item.toString()),
            onTap: () {
              acceptList(context, item);
            },
          );
        },
      ),
    );
  }

  static void refreshSupportList() {
    newSupportList = SupportManager().supportList;
  }

  void acceptList(BuildContext context, SupportItem item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('求救內容:'),
              Text('  ${item.message}'),
              const Text('是否前往救援?'),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('否'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('是'),
              onPressed: () {
                setState(() {
                  selectedSupportItem = item;
                });
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RescueOperation(
                      rescueOperationtitle: '正在進行救援行動',
                      supportItem: item,
                    ),
                  ),
                ).then((result) {
                  refreshSupportList();
                });
              },
            ),
          ],
        );
      },
    );
  }
}//通知欄

class RescueOperation extends StatefulWidget {
  final String rescueOperationtitle;
  final SupportItem supportItem;

  RescueOperation({Key? key, required this.rescueOperationtitle, required this.supportItem}) : super(key: key);

  @override
  State<RescueOperation> createState() => _RescueOperationState();
}

class _RescueOperationState extends State<RescueOperation> {
  String _title = '正在進行救援行動';
  SupportManager supportManager = SupportManager();
  late SupportItem _supportItem;
  late MysqlManager mysqlManager = MysqlManager();

  Set<Marker> markers = {};
  Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _initialCameraPosition; // 將類型更改為可為空的 CameraPosition?
  Timer? _uploadSosIconTimer;//更新圖標位置之計時器
  bool isAEDButtonPressed = false;

  late Position currentPosition;

  @override
  void initState() {
    initstatestep();
    _getCurrentLocation(); // 取得目前位置
    super.initState();
  }
  Future<void> initstatestep() async {
    _supportItem = widget.supportItem;
    mysqlManager = MysqlManager(); // 初始化 MysqlManager
    await mysqlManager.initConnection();
    Position position = await mysqlManager.getUserCurrentLocation();
    double lat = position.latitude;
    double lon = position.longitude;
    await mysqlManager.insertCertainIdTable(_supportItem.ids, uid, lat, lon);
    mysqlManager.startUploadTableIdTimer(context,_supportItem.ids,uid);//開始上傳自身位置
    _title = widget.rescueOperationtitle;
    List<double> latLon = await mysqlManager.queryIdDistressSignalTable(_supportItem.ids);
    _uploadSosIconTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _createCustomMarker(latLon);
    });//每兩秒更新一次圖標
  }

  @override
  void dispose() {
    mysqlManager.stopUploadTableIdTimer(); //停止上傳自身位置
    _uploadSosIconTimer?.cancel();
    mysqlManager.deleteCertainIdTablePosition(_supportItem.ids, uid);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialCameraPosition == null) {
      // 目前相機位置尚未初始化，可以顯示一個 Loading
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,//很重要!!!!!!!!!!!(返回鍵去除)
          centerTitle: true,
          title: Text(_title),
          //title: Text('${_supportItem.ids},${_supportItem.message},${_supportItem.distanceInMeters}'),
          leading: null,
        ),
        body: SafeArea(
          child: GoogleMap(
            markers: markers.union(markers), // 将显示所有标记和自定义标记
            initialCameraPosition: _initialCameraPosition ??
                const CameraPosition(target: LatLng(25.042587, 121.532946), zoom: 16),
            mapType: MapType.normal,
            myLocationEnabled: true,
            compassEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const SizedBox(width: 1),
              ElevatedButton(
                onPressed: () {
                  //mysqlManager.stopUploadTimer4();
                  mysqlManager.deleteCertainIdTablePosition(_supportItem.ids,uid);
                  Navigator.of(context).pop(); // 回上一頁
                  Navigator.of(context).pop(); // 回上一頁
                  Navigator.of(context).pop(); // 回上一頁
                },
                child: const Text('取消支援', style: TextStyle(fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: _showMultipleMarkers,
                child: Text(isAEDButtonPressed ? 'Hide AED' : 'Show AED', style: TextStyle(fontSize: 16)),
              ),
              /*ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CloudMysql(cloudtitle: '雲端測試'),
                    ),
                  );
                },//測試階段，先不用放AED功能
                child: const Text('AED', style: TextStyle(fontSize: 16)),
              ),*/
              const SizedBox(width: 1),
            ],
          ),
        )
    );
  }

  Future<void> _createCustomMarker(List<double> lathLon1) async {
    const double scale = 2.0;
    const double originalWidth = 64.0;
    const double originalHeight = 64.0;
    final int newWidth = (originalWidth * scale).toInt();
    final int newHeight = (originalHeight * scale).toInt();
    final Uint8List customIconData = await _getBytesFromAsset('assets/image/sos_marker.png', newWidth, newHeight);
    final BitmapDescriptor customIcon = BitmapDescriptor.fromBytes(customIconData);

    final double lat1 = lathLon1[0];
    final double lon1 = lathLon1[1];

    final MarkerId markerId = MarkerId('device_marker'); //標記的ID
    Marker? existingMarker;
    for (final marker in markers) {
      if (marker.markerId == markerId) {
        existingMarker = marker;
        break;
      }
    }

    if (existingMarker != null) {
      setState(() {
        markers = markers.difference({existingMarker}); //移除舊的標記
        markers.add(existingMarker!.copyWith(positionParam: LatLng(lat1, lon1),)); // 加上更新的標記
      });
    } else {
      final Marker newMarker = Marker(
        markerId: markerId,
        position: LatLng(lat1, lon1),
        icon: customIcon,
      );
      setState(() {
        markers.add(newMarker); // 加上更新的標記
      });
    }
  }

  void _getCurrentLocation() async {
    // 使用者給予了位置權限
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _initialCameraPosition = CameraPosition(
        target: LatLng(position.latitude, position.longitude),
        zoom: 16,
      );
    });
  }

  Future<Uint8List> _getBytesFromAsset(String path, int newWidth, int newHeight) async {
    final ByteData data = await rootBundle.load(path);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: newWidth, targetHeight: newHeight);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    return (await frameInfo.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  } //創建圖像的地方

  Future<void> _showMultipleMarkers() async {
    setState(() {
      if (isAEDButtonPressed) {
        // 如果 isAEDButtonPressed為true，清除所有標記
        markers.clear();
        isAEDButtonPressed = false;
      } else {
        // 如果 isAEDButtonPressed為false，添加標記
        markers.addAll(getMarkers());
        isAEDButtonPressed = true;
      }
    });
  }
}//救援行動頁面

class SaveMap extends StatefulWidget {
  final String savetitle;
  const SaveMap({Key? key, required this.savetitle}) : super(key: key);

  @override
  State<SaveMap> createState() => _SaveMapState();
}

class _SaveMapState extends State<SaveMap> {
  late MysqlManager mysqlManager;
  int a = 0;

  String _title = '救援端-一般模式';

  Widget _body = Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Expanded(
        child: Image.asset(
          'assets/image/1.png',
          fit: BoxFit.cover,
        ),
      ),
    ],
  );

  @override
  void dispose() {
    if(a==2) {
      stopUpload(); // 在這裡呼叫 stopTimer()
      super.dispose();
    }else {
      super.dispose();
    }
  }//a==2是在任務模式的頁面

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(_title),
        ),
        body: _body,
        bottomNavigationBar: BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _toggleTitle,
                child: const Text('切换模式'),
              ),
            ],
          ),
        )
    );
  }

  void startUpload() {
    mysqlManager = MysqlManager(); // 初始化 MysqlManager
    mysqlManager.initConnection();
    mysqlManager.startUploadUserPositionTimer(uid); // 定時上傳位置
  }

  void stopUpload() async {
    mysqlManager.stopUploadUserPositionTimer(); // 停止計時
    mysqlManager.deleteIdUserPositionTable(uid);
    await Future.delayed(Duration(seconds: 3));
    mysqlManager.dispose(); // 關閉數據庫
  }

  void _toggleTitle() {
    setState(() {
      if (_title == '救援端-一般模式') {
        a=2;
        _title = '救援端-任務模式';
        _body = Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Image.asset(
                'assets/image/2.png',
                fit: BoxFit.cover,
              ),
            ),
          ],
        );
      } else {
        a=0;
        _title = '救援端-一般模式';
        _body = Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Image.asset(
                'assets/image/1.png',
                fit: BoxFit.cover,
              ),
            ),
          ],
        );
      }
      if(a==2){
        startUpload();
      }else{
        stopUpload();
      }
    });
  }//切換觸發


}//救援端介面(救護車)

class SendSave extends StatefulWidget {
  final String sendtitle;
  const SendSave({Key? key, required this.sendtitle}) : super(key: key);

  @override
  State<SendSave> createState() => _SendSaveState();
}

class _SendSaveState extends State<SendSave> {
  final TextEditingController _textEditingController = TextEditingController();
  late MysqlManager mysqlManager;
  String _title = '發出求救';

  @override
  void initState() {
    super.initState();
    _title = widget.sendtitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_title),
      ),
      body: SingleChildScrollView(
        child:Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 5,),
                Container(
                  width: 275,
                  child:TextField(
                    controller: _textEditingController,
                    decoration: const InputDecoration(
                      labelText: '說明遇到狀況',
                      labelStyle: TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(20 , 15)
                  ),
                  onPressed: () async {
                    var inputText = _textEditingController.text;
                    final mysqlManager = MysqlManager();
                    Position position = await mysqlManager.getUserCurrentLocation();
                    double lat = position.latitude;
                    double lon = position.longitude;
                    await mysqlManager.initConnection();
                    await mysqlManager.insertDistressSignal(uid,lat,lon,inputText);
                    mysqlManager.dispose();
                    _textEditingController.clear();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WaitForSave(WaitFortitle: '求救中',)),);
                  },
                  child: const Text('送出',style: TextStyle(fontSize: 20),),
                ),
              ],
            ),
            const SizedBox(height: 20,),
            Column(
              children: [
                const SizedBox(height: 70,),
                ElevatedButton(
                  onPressed: () async {
                    final mysqlManager = MysqlManager();
                    Position position = await mysqlManager.getUserCurrentLocation();
                    double latitude = position.latitude;
                    double longitude = position.longitude;
                    await mysqlManager.initConnection();
                    await mysqlManager.insertDistressSignal(uid,latitude,longitude,'需要AED');
                    mysqlManager.dispose();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WaitForSave(WaitFortitle: '求救中',)),);
                  },
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200 , 100)
                  ),
                  child: const Text('需要AED',style: TextStyle(fontSize: 24),),
                ),
                const SizedBox(height: 70,),
                ElevatedButton(
                  onPressed: () async {
                    final mysqlManager = MysqlManager();
                    Position position = await mysqlManager.getUserCurrentLocation();
                    double latitude = position.latitude;
                    double longitude = position.longitude;
                    await mysqlManager.initConnection();
                    await mysqlManager.insertDistressSignal(uid,latitude,longitude,'其他緊急事件');
                    mysqlManager.dispose();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WaitForSave(WaitFortitle: '求救中',)),);
                  },
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200 , 100)
                  ),
                  child: const Text('其他緊急事件',style: TextStyle(fontSize: 24),),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}//求救

class WaitForSave extends StatefulWidget {
  final String WaitFortitle;
  const WaitForSave({Key? key, required this.WaitFortitle}) : super(key: key);

  @override
  State<WaitForSave> createState() => _WaitForSaveState();
}

class _WaitForSaveState extends State<WaitForSave> {
  String _title = '求救中';
  late MysqlManager mysqlManager;

  Set<Marker> markers = {};
  Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _initialCameraPosition; // 將類型更改為可為空的 CameraPosition?
  Timer? _updateSupportIconTimer;
  bool isAEDButtonPressed = false;

  @override
  void initState() {
    super.initState();
    _title = widget.WaitFortitle;
    _getCurrentLocation(); // 取得目前位置
    startUpload();
  }


  void updateSupportIcon(){
    _updateSupportIconTimer = Timer.periodic(const Duration(seconds: 2), (timer) async{
      List<Map<String, dynamic>> supportPosition = [];
      await mysqlManager.querySupportPosition(supportPosition, uid); // 本體發出求救建立的table維自身的id

      setState(() {
        if (supportPosition.isNotEmpty) {
          _createCustomMarkers(supportPosition);
        } else {
          markers.clear(); // 清除已經存在的標記
          if(isAEDButtonPressed == true) {
            markers.addAll(getMarkers());
          }
        }
      });
    });
  }

  @override
  void dispose() {
    stopUpload();
    _updateSupportIconTimer?.cancel();
    mysqlManager.deleteUidDistressSignal(uid);
    notificationBarState.newSupportList.clear();
    super.dispose();
  }//離開頁面時停止上傳

  @override
  Widget build(BuildContext context) {
    if (_initialCameraPosition == null) {
      // 目前相機位置尚未初始化，可以顯示一個 Loading
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(_title),
        ),
        body: SafeArea(
          child: GoogleMap(
            markers: markers.union(markers), // 顯示所有標記
            initialCameraPosition: _initialCameraPosition ??
                CameraPosition(target: LatLng(25.042587, 121.532946), zoom: 16),
            mapType: MapType.normal,
            myLocationEnabled: true,
            compassEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const SizedBox(width: 5),
              ElevatedButton(
                onPressed: (){
                  save_cancel(context);
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: (){
                  save_end(context);
                },
                child: const Text('救援結束'),
              ),
              ElevatedButton(
                onPressed: _showMultipleMarkers,
                child: Text(isAEDButtonPressed ? 'Hide AED' : 'Show AED', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 5),
            ],
          ),
        )
    );
  }//整體畫面

  void save_end(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const Text('是否要結束求救?'),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop(); // 回上一頁
              },
            ),
            TextButton(
              child: const Text('確定'),
              onPressed: () {
                stopUpload();
                Navigator.of(context).pop(); // 回上一頁
                Navigator.of(context).pop(); // 回上一頁
                Navigator.of(context).pop(); // 回上一頁
              },
            ),
          ],
        );
      },
    );
  }//按下結束後的彈跳視窗
  void save_cancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const Text('確定要取消求救?'),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop(); // 回上一頁
              },
            ),
            TextButton(
              child: const Text('確定'),
              onPressed: () {
                stopUpload();
                Navigator.of(context).pop(); // 回上一頁
                Navigator.of(context).pop(); // 回上一頁
                Navigator.of(context).pop(); // 回上一頁
              },
            ),
          ],
        );
      },
    );
  }//按下取消後的彈跳視窗

  void startUpload() async{
    mysqlManager = MysqlManager(); // 初始化 MysqlManager
    await mysqlManager.initConnection();
    mysqlManager.startUploadDistressSignalTimer(uid); // 定時上傳位置
    updateSupportIcon(); // 更新支援者圖示
  }
  void stopUpload() async {
    mysqlManager.stopUploadDistressSignalTimer(); // 停止計時
    await mysqlManager.deleteUidDistressSignal(uid);
    await mysqlManager.deleteUidTable(uid);
    await Future.delayed(Duration(seconds: 3));
    mysqlManager.dispose(); // 關閉數據庫
  }

  void _getCurrentLocation() async {
    // 使用者給予了位置權限
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _initialCameraPosition = CameraPosition(
        target: LatLng(position.latitude, position.longitude),
        zoom: 16,
      );
    });
  }

  //支援者圖示
  Future<void> _createCustomMarkers(List<Map<String, dynamic>> positions) async {
    final Uint8List customIconData = await _getBytesFromAsset('assets/image/green_star.png');
    final BitmapDescriptor customIcon = BitmapDescriptor.fromBytes(customIconData);

    for (var position in positions) {
      final int id = position['id'];
      final double lat = position['lat'];
      final double lon = position['lon'];
      final MarkerId markerId = MarkerId('device_marker_$id');
      print('經緯度:$lat,$lon,ID值:$id');

      Marker? existingMarker;
      for (final marker in markers) {
        if (marker.markerId == markerId) {
          existingMarker = marker;
          break;
        }
      }

      if (existingMarker != null) {
        setState(() {
          markers = markers.difference({existingMarker});
          markers.add(existingMarker!.copyWith(positionParam: LatLng(lat, lon)));
        });
      } else {
        final Marker newMarker = Marker(
          markerId: markerId,
          position: LatLng(lat, lon),
          icon: customIcon,
          anchor: const Offset(0.5, 1),
        );
        setState(() {
          markers.add(newMarker);
        });
      }
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path) async {
    final ByteData data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  } //創建圖像的地方

  Future<void> _showMultipleMarkers() async {
    setState(() {
      if (isAEDButtonPressed) {
        // 如果 isAEDButtonPressed為true，清除所有標記
        markers.clear();
        isAEDButtonPressed = false;
      } else {
        // 如果 isAEDButtonPressed為false，添加標記
        markers.addAll(getMarkers());
        isAEDButtonPressed = true;
      }
    });
  }
}//等待求救的畫面

class LoginPage extends StatefulWidget {
  final String logintitle;
  const LoginPage({Key? key, required this.logintitle}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController _usernameLogin = TextEditingController();
  TextEditingController _passwordLogin = TextEditingController();
  String _title = '登入系統';

  @override
  void initState() {
    super.initState();
    _title = widget.logintitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_title),
        leading: null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32.0),
              TextField(
                controller: _usernameLogin,
                decoration: const InputDecoration(
                  labelText: '帳號',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _passwordLogin,
                decoration: const InputDecoration(
                  labelText: '密碼',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: () {
                  _login();
                },
                child: const Text('登入'),
              ),
              const SizedBox(height: 16.0),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegistrationPage(RegistrationPagetitle: '註冊頁面',)),);
                },
                child: const Text('註冊'),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Future<void> _login() async {
    String username1 = _usernameLogin.text;
    String password1 = _passwordLogin.text;
    final mysqlManager = MysqlManager();
    await mysqlManager.initConnection();
    try {
      // 查詢符合條件的使用者
      var results = await mysqlManager.conn.query(
        'SELECT * FROM account WHERE username = ? AND password = ?',
        [username1, password1],
      );

      if (results.isNotEmpty) {
        // 若結果不為空，代表找到了符合條件的使用者
        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SaveMap(savetitle: '救援端-一般模式',)),);
        // 在這裡可以執行相應的處理邏輯
      } else {
        // 若結果為空，代表未找到符合條件的使用者
        _failed(context);
        // 在這裡可以執行相應的處理邏輯
      }
    } catch (e) {
      print('查詢資料時發生錯誤：$e');
      // 在這裡可以處理錯誤情況
    }
    mysqlManager.dispose();
  }

  void _failed(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('登入失敗'),
          content: const Text('請再試一次!'),
          actions: [
            TextButton(
              child: const Text('確定'),
              onPressed: () {
                Navigator.of(context).pop(); // 關閉弹窗
              },
            ),
          ],
        );
      },
    );
  }//登入失敗後的彈跳視窗
}//登入頁面

class RegistrationPage extends StatefulWidget {
  final String RegistrationPagetitle;
  const RegistrationPage({Key? key, required this.RegistrationPagetitle}) : super(key: key);

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  TextEditingController _usernameController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('註冊'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '帳號',
              ),
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '密碼',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () async {
                String username = _usernameController.text;
                String password = _passwordController.text;
                final mysqlManager = MysqlManager();
                await mysqlManager.initConnection();
                try {
                  // 查詢符合條件的使用者
                  var results = await mysqlManager.conn.query(
                    'SELECT * FROM account WHERE username = ?',
                    [username],
                  );

                  if (results.isEmpty) {
                    // 沒有重複的帳密
                    await mysqlManager.insertAccount(username,password);
                    _showDialog(context);
                  } else {
                    // 帳密重複
                    _duplicate_Account(context);
                    // 在這裡可以執行相應的處理邏輯
                  }
                } catch (e) {
                  print('查詢資料時發生錯誤：$e');
                  // 在這裡可以處理錯誤情況
                }
                // 執行註冊操作，例如發送請求到後端API
                // 驗證輸入的資訊並創建新的用戶帳號
                // 註冊成功後，可以導航到登入頁面或其他相關頁面
              },
              child: const Text('註冊'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('註冊成功通知'),
          content: const Text('註冊成功!'),
          actions: [
            TextButton(
              child: const Text('回到登入畫面'),
              onPressed: () {
                Navigator.of(context).pop(); // 回上一頁
                Navigator.of(context).pop(); // 回上一頁
              },
            ),
          ],
        );
      },
    );
  }//註冊成功後的彈跳視窗

  void _duplicate_Account(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('註冊失敗通知'),
          content: const Text('帳號重複:('),
          actions: [
            TextButton(
              child: const Text('再試一次'),
              onPressed: () {
                Navigator.of(context).pop(); // 關閉弹窗
              },
            ),
          ],
        );
      },
    );
  }//註冊失敗後的彈跳視窗
}//註冊頁面