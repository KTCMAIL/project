class MyPosition {
  final int id;
  final DateTime time;
  final double latitude;
  final double longitude;

//required這表示在創建物件時，這些參數是必須提供的
//?可為空、:為初始化列表
  MyPosition({
    required this.id,
    DateTime? time,
    required this.latitude,
    required this.longitude,
  }) : time = time ?? DateTime.timestamp().add(const Duration(hours: 8));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time.toString(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}