/// Where this phone stands with notifications.
enum PushStatus {
  /// The browser can't do notifications.
  unsupported,

  /// iPhone: add the app to the home screen first.
  install,

  /// Not asked yet.
  notAsked,
  granted,
  denied,
}

/// One subscribed phone.
class PushDevice {
  const PushDevice({required this.endpoint, required this.p256dh, required this.auth});
  final String endpoint;
  final String p256dh;
  final String auth;
}

class PushError implements Exception {
  const PushError(this.reason);

  /// 'denied', 'default' (dismissed), 'unsupported' or a browser message.
  final String reason;

  @override
  String toString() => 'PushError: $reason';
}
