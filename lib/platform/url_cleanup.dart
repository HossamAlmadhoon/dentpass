// Removes "?reset=1" (and any sign-in leftovers) from the web address after use,
// so reloading the page doesn't open "Set a new password" again.
export 'url_cleanup_stub.dart' if (dart.library.js_interop) 'url_cleanup_web.dart';
