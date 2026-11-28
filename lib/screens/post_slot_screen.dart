import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/maps.dart';
import 'package:dentpass/ui/widgets.dart';

const _maxPhotos = 6;

/// A photo on the form: one already saved (a path) or one just picked (a file).
class _Photo {
  _Photo.saved(this.path) : file = null;
  _Photo.picked(this.file) : path = null;
  final String? path;
  final XFile? file;
}

/// Post a new slot, or edit one ([existing]) after posting.
class PostSlotScreen extends StatefulWidget {
  const PostSlotScreen({super.key, required this.onPosted, this.existing, this.template});

  /// Called with the slot's id after posting or saving.
  final ValueChanged<String> onPosted;

  /// Edit this slot.
  final Slot? existing;

  /// Start a new slot from a copy of this one (date and photos are left for the host to set).
  final Slot? template;

  @override
  State<PostSlotScreen> createState() => _PostSlotScreenState();
}

class _PostSlotScreenState extends State<PostSlotScreen> {
  final _form = GlobalKey<FormState>();
  late final Slot? _old = widget.existing ?? widget.template;
  late final _title = TextEditingController(text: _old?.title ?? '');
  late final _details = TextEditingController(text: _old?.description ?? '');
  late final _address = TextEditingController(text: _old?.address ?? '');
  late final _price = TextEditingController(text: _old == null ? '' : '${_old.priceEgp}');
  late bool _negotiable = _old?.negotiable ?? false;
  final _instapay = TextEditingController();
  String _savedInstapay = '';
  int? _feePercent;
  late SlotKind _kind = _old?.kind ?? SlotKind.observe;
  late String? _area = _old?.area;
  late DateTime? _date = widget.template != null ? null : _old?.startsAt;
  late TimeOfDay _from = _old == null ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay.fromDateTime(_old.startsAt);
  late TimeOfDay _to = _old == null ? const TimeOfDay(hour: 14, minute: 0) : TimeOfDay.fromDateTime(_old.endsAt);
  late int _capacity = _old?.capacity ?? 3;
  late MemberRole _needRole = _old?.needRole ?? MemberRole.dentist;
  late final List<_Photo> _photos = [
    if (widget.existing != null) for (final p in widget.existing!.photoPaths) _Photo.saved(p),
  ];
  late LatLng? _location = (_old != null && _old.hasLocation) ? LatLng(_old.lat!, _old.lng!) : null;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _address.dispose();
    _price.dispose();
    _instapay.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Where guests pay: kept on the profile, filled in here the first time
    repo.feePercent().then((f) {
      if (mounted) setState(() => _feePercent = f);
    }).catchError((_) {});
    repo.myProfile().then((p) {
      if (!mounted) return;
      _savedInstapay = p.instapay ?? '';
      if (_instapay.text.isEmpty) _instapay.text = _savedInstapay;
    }).catchError((_) {});
  }

  void _setKind(SlotKind k) => setState(() {
        _kind = k;
        _capacity = (k == SlotKind.observe || k == SlotKind.course) ? 3 : 1;
      });

  DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: (_date != null && !_date!.isBefore(first)) ? _date! : now.add(const Duration(days: 1)),
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _from : _to);
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _addPhoto() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600, limit: _maxPhotos - _photos.length);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files.take(_maxPhotos - _photos.length).map(_Photo.picked)));
  }

  Future<void> _pickLocation() async {
    final p = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _location)),
    );
    if (p != null) setState(() => _location = p);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_date == null || _area == null) {
      setState(() => _error = t.required);
      return;
    }
    final start = _at(_date!, _from);
    final end = _at(_date!, _to);
    if (!end.isAfter(start)) {
      setState(() => _error = t.errEndBeforeStart);
      return;
    }
    if (!start.isAfter(DateTime.now())) {
      setState(() => _error = t.errPastDate);
      return;
    }

    setState(() => _busy = true);
    try {
      final paths = <String>[];
      var n = 0;
      for (final p in _photos) {
        if (p.path != null) {
          paths.add(p.path!);
        } else {
          n++;
          paths.add(await repo.uploadImage('slot-photos', '${DateTime.now().millisecondsSinceEpoch}-$n.jpg', p.file!));
        }
      }
      final instapay = _instapay.text.trim();
      if (_kind != SlotKind.cover && instapay != _savedInstapay) {
        await repo.saveInstapay(instapay);
        _savedInstapay = instapay;
      }
      if (_editing) {
        final id = _old!.id;
        await repo.updateSlot(
          _old.id,
          title: _title.text.trim(),
          description: _details.text.trim(),
          area: _area!,
          address: _address.text.trim(),
          startsAt: start,
          endsAt: end,
          capacity: _capacity,
          priceEgp: int.tryParse(_price.text) ?? 0,
          needRole: _kind == SlotKind.cover ? _needRole : null,
          photoPaths: paths,
          lat: _location?.latitude,
          lng: _location?.longitude,
          negotiable: _negotiable,
        );
        await repo.removeSlotPhotos(_old.photoPaths.where((p) => !paths.contains(p)).toList());
        widget.onPosted(id);
      } else {
        final id = await repo.createSlot(
          kind: _kind,
          title: _title.text.trim(),
          description: _details.text.trim(),
          area: _area!,
          address: _address.text.trim(),
          startsAt: start,
          endsAt: end,
          capacity: _capacity,
          priceEgp: int.tryParse(_price.text) ?? 0,
          needRole: _kind == SlotKind.cover ? _needRole : null,
          photoPaths: paths,
          lat: _location?.latitude,
          lng: _location?.longitude,
          negotiable: _negotiable,
        );
        widget.onPosted(id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final capacityLabel = switch (_kind) {
      SlotKind.observe || SlotKind.course => t.seats,
      SlotKind.rent => t.chairs,
      SlotKind.cover => t.peopleNeeded,
    };
    final priceLabel = switch (_kind) {
      SlotKind.observe || SlotKind.course => t.pricePerSeat,
      SlotKind.rent => t.priceForSlot,
      SlotKind.cover => t.payForShift,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? t.editSlot : widget.template != null ? t.postCopy : t.postTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            if (!_editing && widget.template == null) ...[
              Text(t.postIntro, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
              const SizedBox(height: 20),
              SectionTitle(t.whatPosting),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  for (final k in SlotKind.values) _KindOption(kind: k, selected: _kind == k, onTap: () => _setKind(k)),
                ],
              ),
              const SizedBox(height: 22),
            ] else ...[
              Row(children: [
                Icon(kindStyle(_kind).icon, color: kindStyle(_kind).ink),
                const SizedBox(width: 8),
                Text(kindName(t, _kind), style: TextStyle(fontWeight: FontWeight.w700, color: kindStyle(_kind).ink)),
              ]),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: InputDecoration(labelText: t.title, hintText: t.titleHint),
              validator: (v) => (v == null || v.trim().length < 3) ? t.errTitleShort : null,
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _details,
              maxLength: 2000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: t.description, hintText: t.descriptionHint, alignLabelWithHint: true),
            ),
            const SizedBox(height: 6),
            SectionTitle(t.photos),
            _PhotoGrid(
              photos: _photos,
              canAdd: _photos.length < _maxPhotos,
              onAdd: _addPhoto,
              onRemove: (i) => setState(() => _photos.removeAt(i)),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _area,
              decoration: InputDecoration(labelText: t.area),
              items: [for (final a in areaKeys) DropdownMenuItem(value: a, child: Text(areaName(context, a)))],
              onChanged: (v) => setState(() => _area = v),
              validator: (v) => v == null ? t.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLength: 300,
              decoration: InputDecoration(labelText: t.address, helperText: t.addressHint),
            ),
            const SizedBox(height: 12),
            SectionTitle(t.location),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickLocation,
                  icon: Icon(_location == null ? Icons.add_location_alt_outlined : Icons.check_circle, color: _location == null ? null : AppColors.nile),
                  label: Text(_location == null ? t.setLocation : t.changeLocation),
                ),
              ),
              if (_location != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: t.removeLocation,
                  onPressed: () => setState(() => _location = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            SectionTitle(t.date),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_date == null ? t.pickDate : fullDate(context, _date!)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _TimeButton(label: t.from, value: _from, onTap: () => _pickTime(true))),
              const SizedBox(width: 10),
              Expanded(child: _TimeButton(label: t.to, value: _to, onTap: () => _pickTime(false))),
            ]),
            const SizedBox(height: 20),
            if (_kind == SlotKind.cover) ...[
              SectionTitle(t.whoNeeded),
              SegmentedButton<MemberRole>(
                segments: [
                  ButtonSegment(value: MemberRole.dentist, label: Text(roleName(t, MemberRole.dentist))),
                  ButtonSegment(value: MemberRole.assistant, label: Text(roleName(t, MemberRole.assistant))),
                ],
                selected: {_needRole},
                onSelectionChanged: (s) => setState(() => _needRole = s.first),
              ),
              const SizedBox(height: 20),
            ],
            Row(children: [
              Expanded(child: Text(capacityLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              IconButton.outlined(
                tooltip: '−',
                onPressed: _capacity > 1 ? () => setState(() => _capacity--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 44,
                child: Text(money(context, _capacity),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              IconButton.outlined(
                tooltip: '+',
                onPressed: _capacity < 100 ? () => setState(() => _capacity++) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: InputDecoration(
                labelText: priceLabel,
                helperText: _kind == SlotKind.cover || _feePercent == null
                    ? null
                    : _feePercent == 0
                        ? t.hostFeeFree
                        : t.hostFeeNote('$_feePercent'),
                helperMaxLines: 2,
              ),
              validator: (v) => (v == null || v.isEmpty) ? t.required : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _negotiable,
              onChanged: (v) => setState(() => _negotiable = v),
              title: Text(t.priceNegotiable, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_kind == SlotKind.cover ? t.priceNegotiableCoverHint : t.priceNegotiableHint),
            ),
            if (_kind != SlotKind.cover) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _instapay,
                textDirection: TextDirection.ltr,
                maxLength: 60,
                decoration: InputDecoration(labelText: t.instapayLabel, hintText: t.instapayHint, helperText: t.instapayHelp),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_editing ? t.saveChanges : t.postIt),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos, required this.canAdd, required this.onAdd, required this.onRemove});
  final List<_Photo> photos;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget thumb(_Photo p) => p.path != null
        ? Image.network(repo.photoUrl(p.path!), fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(color: AppColors.track))
        : FutureBuilder(
            future: p.file!.readAsBytes(),
            builder: (context, snap) =>
                snap.hasData ? Image.memory(snap.data!, fit: BoxFit.cover) : Container(color: AppColors.track),
          );

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (var i = 0; i < photos.length; i++)
          Stack(fit: StackFit.expand, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: thumb(photos[i])),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54, minimumSize: const Size(32, 32)),
                iconSize: 18,
                tooltip: AppLocalizations.of(context).delete,
                onPressed: () => onRemove(i),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ]),
        if (canAdd)
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.field, width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onAdd,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_a_photo_outlined, color: AppColors.muted),
                const SizedBox(height: 4),
                Text(t.addPhoto, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({required this.kind, required this.selected, required this.onTap});
  final SlotKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ks = kindStyle(kind);
    return Material(
      color: selected ? ks.tint : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? ks.ink : AppColors.field, width: selected ? 2 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(ks.icon, size: 18, color: selected ? ks.ink : AppColors.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(kindName(t, kind),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(kindLine(t, kind),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.3, color: selected ? ks.ink : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.value, required this.onTap});
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.muted)),
        ),
        const SizedBox(width: 8),
        Text(time(context, DateTime(2000, 1, 1, value.hour, value.minute))),
      ]),
    );
  }
}
