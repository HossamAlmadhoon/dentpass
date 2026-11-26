import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

class PostSlotScreen extends StatefulWidget {
  const PostSlotScreen({super.key, required this.onPosted});
  final VoidCallback onPosted;

  @override
  State<PostSlotScreen> createState() => _PostSlotScreenState();
}

class _PostSlotScreenState extends State<PostSlotScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _address = TextEditingController();
  final _price = TextEditingController();
  SlotKind _kind = SlotKind.observe;
  String? _area;
  DateTime? _date;
  TimeOfDay _from = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 14, minute: 0);
  int _capacity = 3;
  MemberRole _needRole = MemberRole.dentist;
  XFile? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _address.dispose();
    _price.dispose();
    super.dispose();
  }

  void _setKind(SlotKind k) => setState(() {
        _kind = k;
        _capacity = (k == SlotKind.observe || k == SlotKind.course) ? 3 : 1;
      });

  DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
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
      String? photoPath;
      if (_photo != null) {
        photoPath = await repo.uploadImage('slot-photos', '${DateTime.now().millisecondsSinceEpoch}.jpg', _photo!);
      }
      await repo.createSlot(
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
        photoPath: photoPath,
      );
      widget.onPosted();
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
      appBar: AppBar(title: Text(t.postTitle, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
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
              children: [for (final k in SlotKind.values) _KindOption(kind: k, selected: _kind == k, onTap: () => _setKind(k))],
            ),
            const SizedBox(height: 22),
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
              decoration: InputDecoration(labelText: priceLabel),
              validator: (v) => (v == null || v.isEmpty) ? t.required : null,
            ),
            const SizedBox(height: 16),
            PhotoPickTile(label: t.photo, hasPhoto: _photo != null, onPicked: (f) => setState(() => _photo = f)),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(t.postIt),
            ),
          ],
        ),
      ),
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
        Text(value.format(context)),
      ]),
    );
  }
}
