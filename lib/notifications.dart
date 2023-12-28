import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notify {
  // 初始化flutterLocalNotificationsPlugin
  static FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  static Completer<void> soundCompleter = Completer<void>(); // 使用 Completer 來確保音檔播放完畢
  static bool isPlayingSound = false; // 音檔是否正在撥放

  // 訊息通知使用前要初始化
  static Future<void> initialize() async {
    var androidInitialize = AndroidInitializationSettings('mipmap/ic_launcher');
    var initializationSettings = InitializationSettings(android: androidInitialize);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }//初始化

  // 訊息通知(填入title、訊息內容)
  static Future<void> showBigTextNotification({var id = 0, required String title, required String body, var payload}) async {
    AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'AIzaSyBsD59kQUg66i7Urs2lyH4CchVMbigi-5o',
      'channel_name',
      playSound: true,
      //sound: RawResourceAndroidNotificationSound('notification'),
      importance: Importance.max,
      priority: Priority.high,
    );

    var not = NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(0, title, body, not);
  }

  //列表的內容包成一封通知
  Future<void> sendNotification(List<String> notifications) async {
    String body = notifications.join('\n');
    await Notify.showBigTextNotification(title: '附近有救援車輛', body: body);
  }

  // 撥放列表內容聲音
  Future<void> playSound(List<String> soundFiles) async {
    // 如果音檔正在撥放，則不觸發新的撥放
    if (isPlayingSound) {
      await soundCompleter.future; // 等待音檔播放完畢
      return; // 返回，不執行後續撥放動作
    }

    isPlayingSound = true; // 表示音檔正在撥放
    soundCompleter = Completer<void>(); // 初始化 Completer
    AudioPlayer audioPlayer = AudioPlayer();
    AudioCache audioCache = AudioCache();
    int currentIndex = 0;

    //預先載入音檔
    for (String filePath in soundFiles) {
      await audioCache.load(filePath);
    }

    audioPlayer.onPlayerStateChanged.listen((state) async {
      if (state == PlayerState.completed) {
        currentIndex++;
        if (currentIndex < soundFiles.length) {
          String filePath = soundFiles[currentIndex];
          await audioPlayer.play(AssetSource(filePath));
          audioPlayer.setPlaybackRate(2);
        } else {
          audioPlayer.dispose();
          isPlayingSound = false; // 音檔撥放結束
          soundCompleter.complete(); // 完成 Completer，表示音檔播放完畢
        }
      }
    });

    //撥放第一個音檔
    if (currentIndex < soundFiles.length) {
      String filePath = soundFiles[currentIndex];
      await audioPlayer.play(AssetSource(filePath));
      audioPlayer.setPlaybackRate(2);
    }

    await soundCompleter.future; // 等待音檔播放完畢

  }

}