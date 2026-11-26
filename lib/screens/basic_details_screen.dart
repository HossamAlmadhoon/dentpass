import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The one step after sign-up: who you are and how to reach you. Papers can wait.
/// (The terms were agreed on the sign-up screen; saving records when.)
class BasicDetailsScreen extends StatefulWidget {
  const BasicDetailsScreen({super.key, required this.profile, required this.onSaved});
  final Profile profile;
  final VoidCallback onSaved;

  @override
  State<BasicDetailsScreen> createState() => _BasicDetailsScreenState();
}

class _BasicDetailsScreenState extends State<BasicDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late MemberRole _role = widget.profile.role;
  late String? _area = widget.profile.area;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.saveBasics(fullName: _name.text.trim(), phone: _phone.text.trim(), role: _role, area: _area!);
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String? needed(String? v) => (v == null || v.trim().isEmpty) ? t.required : null;

    return Scaffold(
      appBar: AppBar(
        actions: [
          const LanguageSwitchButton(),
          IconButton(tooltip: t.signOut, icon: const Icon(Icons.logout), onPressed: repo.signOut),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(t.basicsTitle, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 8),
              Text(t.basicsIntro, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.body)),
              const SizedBox(height: 22),
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
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.fullName),
                validator: needed,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.phone, hintText: '01xxxxxxxxx'),
                validator: (v) =>
                    (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) ? t.required : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _area,
                decoration: InputDecoration(labelText: t.area),
                items: [for (final a in areaKeys) DropdownMenuItem(value: a, child: Text(areaName(context, a)))],
                onChanged: (v) => setState(() => _area = v),
                validator: (v) => v == null ? t.required : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(t.startUsing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
