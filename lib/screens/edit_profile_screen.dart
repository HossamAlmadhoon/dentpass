import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

/// Change what others see: photo, about you, area and phone. Checked details stay locked.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final Profile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _bio = TextEditingController(text: widget.profile.bio);
  late String? _area = widget.profile.area;
  XFile? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var avatar = widget.profile.avatarPath;
      if (_photo != null) {
        // A new name each time, so phones don't keep showing the old cached photo
        avatar = await repo.uploadImage('avatars', 'avatar-${DateTime.now().millisecondsSinceEpoch}.jpg', _photo!);
      }
      await repo.updateProfile(phone: _phone.text.trim(), area: _area!, bio: _bio.text.trim(), avatarPath: avatar);
      final old = widget.profile.avatarPath;
      if (_photo != null && old != null) {
        try {
          await repo.db.storage.from('avatars').remove([old]);
        } catch (_) {}
      }
      if (!mounted) return;
      showMessage(context, t.profileSaved);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = widget.profile;
    return Scaffold(
      appBar: AppBar(title: Text(t.editProfile, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Center(
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _pickPhoto,
                child: Stack(children: [
                  _photo != null
                      ? FutureBuilder(
                          future: _photo!.readAsBytes(),
                          builder: (context, snap) => CircleAvatar(
                            radius: 48,
                            backgroundColor: AppColors.track,
                            foregroundImage: snap.hasData ? MemoryImage(snap.data!) : null,
                          ),
                        )
                      : Avatar(
                          name: p.fullName,
                          photoUrl: p.avatarPath == null ? null : repo.avatarUrl(p.avatarPath!),
                          radius: 48,
                        ),
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.nile,
                      child: Icon(Icons.photo_camera_outlined, size: 18, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: TextButton(onPressed: _pickPhoto, child: Text(t.profilePhoto))),
            const SizedBox(height: 10),
            Text(p.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(t.lockedDetails, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
            const SizedBox(height: 18),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.phone),
              validator: (v) => (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) ? t.required : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _area,
              decoration: InputDecoration(labelText: t.area),
              items: [for (final a in areaKeys) DropdownMenuItem(value: a, child: Text(areaName(context, a)))],
              onChanged: (v) => setState(() => _area = v),
              validator: (v) => v == null ? t.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bio,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: t.bio, hintText: t.bioHint, alignLabelWithHint: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(t.saveChanges),
            ),
          ],
        ),
      ),
    );
  }
}
