import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/services/location.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';

// Map tiles from OpenStreetMap. Fine for a pilot; for heavy use switch to a paid tile
// provider (for example MapTiler or Stadia Maps) by changing this one line.
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

Widget _tileLayer() => TileLayer(urlTemplate: _tiles, userAgentPackageName: 'com.dentpass.app');

Widget _attribution() => RichAttributionWidget(
      attributions: [
        TextSourceAttribution(
          'OpenStreetMap contributors',
          onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
        ),
      ],
    );

Widget _pin(SlotKind kind, {double size = 40}) {
  final ks = kindStyle(kind);
  return Icon(Icons.location_on, size: size, color: ks.ink, shadows: const [Shadow(color: Colors.white, blurRadius: 6)]);
}

/// Explore's map: one pin per slot with a location.
class SlotsMap extends StatelessWidget {
  const SlotsMap({super.key, required this.slots, required this.onSelect, this.me});
  final List<Slot> slots;
  final ValueChanged<Slot> onSelect;
  final LatLng? me;

  @override
  Widget build(BuildContext context) {
    final placed = slots.where((s) => s.hasLocation).toList();
    final points = [for (final s in placed) LatLng(s.lat!, s.lng!), if (me != null) me!];
    return FlutterMap(
      options: MapOptions(
        initialCenter: points.isEmpty ? cairo : points.first,
        initialZoom: 11,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15)
            : null,
      ),
      children: [
        _tileLayer(),
        MarkerLayer(markers: [
          for (final s in placed)
            Marker(
              point: LatLng(s.lat!, s.lng!),
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: GestureDetector(onTap: () => onSelect(s), child: _pin(s.kind)),
            ),
          if (me != null)
            Marker(
              point: me!,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3B7BD9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
        ]),
        _attribution(),
      ],
    );
  }
}

/// The small map on a slot's page: a circle for the approximate area, or a pin for the exact spot.
class SlotMiniMap extends StatelessWidget {
  const SlotMiniMap({super.key, required this.slot});
  final Slot slot;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final point = LatLng(slot.lat!, slot.lng!);
    final ks = kindStyle(slot.kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 180,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: slot.exactLocation ? 15 : 13.5,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              _tileLayer(),
              if (slot.exactLocation)
                MarkerLayer(markers: [
                  Marker(point: point, width: 44, height: 44, alignment: Alignment.topCenter, child: _pin(slot.kind)),
                ])
              else
                CircleLayer(circles: [
                  CircleMarker(
                    point: point,
                    radius: 900,
                    useRadiusInMeter: true,
                    color: ks.ink.withValues(alpha: 0.15),
                    borderColor: ks.ink,
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              _attribution(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      if (slot.exactLocation)
        TextButton.icon(
          onPressed: () => launchUrl(mapsLink(slot.lat!, slot.lng!), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.directions_outlined),
          label: Text(t.openInMaps),
        )
      else
        Text(t.approxLocation, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
    ]);
  }
}

/// Tap the map to place the slot's pin. Returns the chosen point.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});
  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  late LatLng? _point = widget.initial;
  bool _locating = false;

  Future<void> _useMine() async {
    setState(() => _locating = true);
    final here = await currentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (here == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).locationDenied)));
      return;
    }
    setState(() => _point = here);
    _map.move(here, 16);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.setLocation, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _point ?? cairo,
            initialZoom: _point == null ? 11 : 16,
            onTap: (_, p) => setState(() => _point = p),
          ),
          children: [
            _tileLayer(),
            if (_point != null)
              MarkerLayer(markers: [
                Marker(
                  point: _point!,
                  width: 48,
                  height: 48,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on, size: 48, color: AppColors.nile),
                ),
              ]),
            _attribution(),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t.pickOnMap, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton.icon(
            onPressed: _locating ? null : _useMine,
            icon: const Icon(Icons.my_location),
            label: Text(t.useMyLocation),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _point == null ? null : () => Navigator.pop(context, _point),
            child: Text(t.confirmLocation),
          ),
        ]),
      ),
    );
  }
}
