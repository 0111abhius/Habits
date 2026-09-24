import 'dart:js_interop';

@JS('Notification')
extension type _JSNotification._(JSObject _) implements JSObject {
  external factory _JSNotification(String title, [JSObject options]);
  external static String get permission;
  external static JSPromise<JSString> requestPermission();
}

@JS('Notification')
external JSAny? get _notificationCtor;

@JS('document.visibilityState')
external String get _visibilityState;

@JS('window.localStorage.getItem')
external JSString? _localGetItem(String key);

@JS('window.localStorage.setItem')
external void _localSetItem(String key, String value);

/// Thin wrapper over the browser Notification API.
class NotificationBridge {
  static bool get isSupported {
    try {
      return _notificationCtor != null;
    } catch (_) {
      return false;
    }
  }

  static String get permission {
    if (!isSupported) return 'unsupported';
    try {
      return _JSNotification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<String> requestPermission() async {
    if (!isSupported) return 'unsupported';
    try {
      final result = await _JSNotification.requestPermission().toDart;
      return result.toDart;
    } catch (_) {
      return permission;
    }
  }

  static void show(String title, {String? body, String? tag, String? icon}) {
    if (permission != 'granted') return;
    try {
      final options = <String, Object?>{
        if (body != null) 'body': body,
        if (tag != null) 'tag': tag,
        'icon': icon ?? 'icons/Icon-192.png',
      }.jsify() as JSObject;
      _JSNotification(title, options);
    } catch (_) {
      // Some browsers (e.g. Chrome on Android) require a service worker; the
      // in-app fallback in ReminderService covers that case.
    }
  }

  static bool get isDocumentVisible {
    try {
      return _visibilityState == 'visible';
    } catch (_) {
      return true;
    }
  }

  static String? localGet(String key) {
    try {
      return _localGetItem(key)?.toDart;
    } catch (_) {
      return null;
    }
  }

  static void localSet(String key, String value) {
    try {
      _localSetItem(key, value);
    } catch (_) {}
  }
}
