import 'dart:convert';
import 'dart:js_interop';

import 'package:dentpass/platform/push_types.dart';

@JS('dentpassPush.status')
external JSString _status();

@JS('dentpassPush.subscribe')
external JSPromise<JSString> _subscribe(JSString publicKey);

@JS('dentpassPush.current')
external JSPromise<JSString> _current();

@JS('dentpassPush.unsubscribe')
external JSPromise<JSString> _unsubscribe();

PushStatus pushStatus() {
  try {
    return switch (_status().toDart) {
      'install' => PushStatus.install,
      'granted' => PushStatus.granted,
      'denied' => PushStatus.denied,
      'default' => PushStatus.notAsked,
      _ => PushStatus.unsupported,
    };
  } catch (_) {
    return PushStatus.unsupported;
  }
}

PushDevice? _device(String raw) {
  if (raw.isEmpty) return null;
  final m = jsonDecode(raw) as Map<String, dynamic>;
  if (m['error'] != null) throw PushError('${m['error']}');
  final keys = (m['keys'] as Map?) ?? const {};
  final endpoint = m['endpoint'] as String?;
  if (endpoint == null || keys['p256dh'] == null || keys['auth'] == null) return null;
  return PushDevice(endpoint: endpoint, p256dh: '${keys['p256dh']}', auth: '${keys['auth']}');
}

Future<PushDevice?> pushCurrent() async {
  try {
    return _device((await _current().toDart).toDart);
  } catch (_) {
    return null;
  }
}

/// Call straight from a tap: iPhones only allow the permission question then.
Future<PushDevice?> pushSubscribe(String publicKey) async => _device((await _subscribe(publicKey.toJS).toDart).toDart);

Future<String?> pushUnsubscribe() async {
  final endpoint = (await _unsubscribe().toDart).toDart;
  return endpoint.isEmpty ? null : endpoint;
}
