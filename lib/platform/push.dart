// Phone notifications: the web app uses web push; other builds report "unsupported" for now.
export 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart';
