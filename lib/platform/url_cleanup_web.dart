import 'package:web/web.dart' as web;

void cleanUpAddressBar() {
  final location = web.window.location;
  if (location.search.isEmpty && location.hash.isEmpty) return;
  web.window.history.replaceState(null, '', location.pathname);
}
