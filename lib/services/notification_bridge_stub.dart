/// Non-web platforms: browser notifications are unavailable.
class NotificationBridge {
  static bool get isSupported => false;

  /// One of `granted`, `denied`, `default`, or `unsupported`.
  static String get permission => 'unsupported';

  static Future<String> requestPermission() async => 'unsupported';

  static void show(String title, {String? body, String? tag, String? icon}) {}

  static bool get isDocumentVisible => true;

  static String? localGet(String key) => null;

  static void localSet(String key, String value) {}
}
