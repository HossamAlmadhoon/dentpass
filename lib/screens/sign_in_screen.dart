import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/services/shared_link.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  // Someone opening a shared slot is most likely new
  bool _signUp = SharedLink.slotId != null;
  bool _agreed = false;
  bool _triedSignUp = false;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_signUp && !_agreed) {
      setState(() => _triedSignUp = true);
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final t = AppLocalizations.of(context);
    try {
      if (_signUp) {
        final res = await repo.signUp(_email.text.trim(), _password.text);
        // With email confirmation on, there is no session until the link is opened.
        if (res.session == null && mounted) {
          setState(() {
            _notice = t.checkEmail;
            _signUp = false;
          });
        }
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _notice = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(actions: const [LanguageSwitchButton()]),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Row(children: [
                const Icon(Icons.verified_outlined, color: AppColors.nile, size: 30),
                const SizedBox(width: 10),
                Text(t.appName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 16),
              if (SharedLink.slotId != null)
                _SharedSlotPreview(slotId: SharedLink.slotId!)
              else
                Text(t.authIntro, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.body)),
              const SizedBox(height: 28),
              Text(_signUp ? t.signUpTitle : t.signInTitle,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.email),
                validator: (v) => (v == null || !v.contains('@') || !v.contains('.')) ? t.emailInvalid : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.password),
                validator: (v) => (v == null || v.length < 8) ? t.passwordTooShort : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_signUp) ...[
                const SizedBox(height: 8),
                TermsAgreement(value: _agreed, onChanged: (v) => setState(() => _agreed = v), showError: _triedSignUp),
              ],
              if (!_signUp)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim())),
                    ),
                    child: Text(t.forgotPassword),
                  ),
                ),
              if (_notice != null) ...[
                const SizedBox(height: 14),
                Text(_notice!, style: const TextStyle(fontSize: 14, color: AppColors.body, height: 1.4)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_signUp ? t.signUp : t.signIn),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _signUp = !_signUp;
                  _notice = null;
                }),
                child: Text(_signUp ? t.haveAccount : t.noAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slot someone shared, shown above sign-up: what it is, when, where, the price.
class _SharedSlotPreview extends StatefulWidget {
  const _SharedSlotPreview({required this.slotId});
  final String slotId;

  @override
  State<_SharedSlotPreview> createState() => _SharedSlotPreviewState();
}

class _SharedSlotPreviewState extends State<_SharedSlotPreview> {
  late final Future<Slot?> _slot = repo.publicSlot(widget.slotId).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<Slot?>(
      future: _slot,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 120);
        final slot = snap.data;
        if (slot == null) {
          return Text(t.sharedSlotGone, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.body));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.sharedSlotIntro, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.body)),
          const SizedBox(height: 12),
          IgnorePointer(child: SlotCard(slot: slot, onTap: () {})),
          if (slot.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(slot.description, maxLines: 4, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.body)),
          ],
        ]);
      },
    );
  }
}
