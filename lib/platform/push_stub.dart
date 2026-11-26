import 'package:dentpass/platform/push_types.dart';

PushStatus pushStatus() => PushStatus.unsupported;

Future<PushDevice?> pushCurrent() async => null;

Future<PushDevice?> pushSubscribe(String publicKey) async => throw const PushError('unsupported');

Future<String?> pushUnsubscribe() async => null;
