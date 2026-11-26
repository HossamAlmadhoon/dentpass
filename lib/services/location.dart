import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Cairo, used to centre the map when nothing better is known.
const cairo = LatLng(30.0444, 31.2357);

/// The phone's current position, or null if location is off or not allowed.
Future<LatLng?> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}

/// Distance in kilometres.
double distanceKm(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b) / 1000;

/// A Google Maps link for a point; it opens the Maps app on phones.
Uri mapsLink(double lat, double lng) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
