import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/data/repo.dart';
import 'package:dentpass/platform/push.dart';
import 'package:dentpass/platform/push_types.dart';

export 'package:dentpass/platform/push_types.dart';

/// Phone notifications for the signed-in member.
class PhoneNotifications extends ChangeNotifier {
  PhoneNotifications._();
  static final instance = PhoneNotifications._();

  String? _publicKey;
  PushStatus status = PushStatus.unsupported;
  bool enabled = false;
  bool busy = false;

  /// Reads the state and loads the key in advance, so a tap can ask right away.
  Future<void> prepare() async {
    status = pushStatus();
    if (status == PushStatus.unsupported || status == PushStatus.install) {
      notifyListeners();
      return;
    }
    final device = await pushCurrent();
    enabled = status == PushStatus.granted && device != null;
    // Keep the saved device up to date (it may belong to whoever used this phone before)
    if (enabled && device != null) {
      try {
        await repo.savePushDevice(endpoint: device.endpoint, p256dh: device.p256dh, auth: device.auth, lang: _lang());
      } catch (_) {}
    }
    try {
      final res = await repo.db.functions.invoke('send-push', method: HttpMethod.get);
      final data = res.data;
      if (data is Map && data['publicKey'] is String && (data['publicKey'] as String).isNotEmpty) {
        _publicKey = data['publicKey'] as String;
      }
    } catch (_) {}
    notifyListeners();
  }

  bool get ready => _publicKey != null;

  String _lang() => PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'ar';

  /// Turns notifications on. Throws [PushError] when the person says no.
  Future<void> enable({required String lang}) async {
    final key = _publicKey;
    if (key == null) throw const PushError('unavailable');
    busy = true;
    notifyListeners();
    try {
      final device = await pushSubscribe(key); // asks first, before any other wait
      if (device == null) throw const PushError('unavailable');
      await repo.savePushDevice(endpoint: device.endpoint, p256dh: device.p256dh, auth: device.auth, lang: lang);
      enabled = true;
    } finally {
      status = pushStatus();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    busy = true;
    notifyListeners();
    try {
      final endpoint = await pushUnsubscribe();
      if (endpoint != null) await repo.removePushDevice(endpoint);
      enabled = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Before signing out: this phone should stop getting the member's notifications.
  Future<void> forgetThisPhone() async {
    try {
      final device = await pushCurrent();
      if (device != null) await repo.removePushDevice(device.endpoint);
    } catch (_) {}
    enabled = false;
  }
}
