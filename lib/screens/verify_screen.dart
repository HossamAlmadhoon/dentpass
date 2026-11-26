import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// New members (or rejected ones) send their details and documents for checking.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.profile, required this.onSubmitted});
  final Profile profile;
  final VoidCallback onSubmitted;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _syndicate = TextEditingController(text: widget.profile.syndicateNo ?? '');
  late MemberRole _role = widget.profile.role;
  late String? _area = widget.profile.area;
  XFile? _card;
  XFile? _id;
  bool _busy = false;
  String? _error;

  bool get _hasCard => _card != null || widget.profile.cardPath != null;
  bool get _hasId => _id != null || widget.profile.idPath != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _syndicate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final formOk = _form.currentState!.validate();
    final docsOk = _hasId && (_role == MemberRole.assistant || _hasCard);
    if (!formOk || !docsOk || _area == null) {
      setState(() => _error = t.required);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var cardPath = widget.profile.cardPath;
      var idPath = widget.profile.idPath;
      if (_role == MemberRole.dentist && _card != null) {
        cardPath = await repo.uploadImage('verification', 'syndicate_card.jpg', _card!, replace: true);
      }
      if (_id != null) idPath = await repo.uploadImage('verification', 'national_id.jpg', _id!, replace: true);
      await repo.submitVerification(
        fullName: _name.text.trim(),
        phone: _phone.text.trim(),
        role: _role,
        syndicateNo: _syndicate.text.trim(),
        area: _area!,
        cardPath: cardPath,
        idPath: idPath!,
      );
      widget.onSubmitted();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rejected = widget.profile.status == VerificationStatus.rejected;
    String? needed(String? v) => (v == null || v.trim().isEmpty) ? t.required : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.verifyTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          const LanguageSwitchButton(),
          IconButton(tooltip: t.signOut, icon: const Icon(Icons.logout), onPressed: repo.signOut),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              if (rejected) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.dangerTint, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.rejectedTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                    if ((widget.profile.rejectionReason ?? '').isNotEmpty)
                      Text(t.rejectedReason(widget.profile.rejectionReason!)),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              Text(t.verifyIntro, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.body)),
              const SizedBox(height: 20),
              SectionTitle(t.iAmA),
              SegmentedButton<MemberRole>(
                segments: [
                  ButtonSegment(value: MemberRole.dentist, label: Text(roleName(t, MemberRole.dentist))),
                  ButtonSegment(value: MemberRole.assistant, label: Text(roleName(t, MemberRole.assistant))),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 18),
              TextFormField(controller: _name, decoration: InputDecoration(labelText: t.fullName), validator: needed),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.phone, hintText: '01xxxxxxxxx'),
                validator: (v) =>
                    (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) ? t.required : null,
              ),
              if (_role == MemberRole.dentist) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _syndicate,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.syndicateNo),
                  validator: needed,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _area,
                decoration: InputDecoration(labelText: t.area),
                items: [for (final a in areaKeys) DropdownMenuItem(value: a, child: Text(areaName(context, a)))],
                onChanged: (v) => setState(() => _area = v),
                validator: (v) => v == null ? t.required : null,
              ),
              const SizedBox(height: 20),
              if (_role == MemberRole.dentist) ...[
                PhotoPickTile(
                  label: t.syndicateCard,
                  hasPhoto: _hasCard,
                  onPicked: (f) => setState(() => _card = f),
                ),
                const SizedBox(height: 10),
              ],
              PhotoPickTile(label: t.nationalId, hasPhoto: _hasId, onPicked: (f) => setState(() => _id = f)),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(t.sendForCheck),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
