import 'package:flutter/material.dart';

import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

/// "Forgot password?": ask for the email and send a reset link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await repo.sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _notice = t.resetSent);
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
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(t.resetTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(t.resetIntro, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.body)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.email),
                validator: (v) => (v == null || !v.contains('@') || !v.contains('.')) ? t.emailInvalid : null,
                onFieldSubmitted: (_) => _send(),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 14),
                Text(_notice!, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.body)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(t.sendLink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Set a new password: after opening the reset link, or from Profile.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.setPassword(_password.text);
      if (!mounted) return;
      showMessage(context, t.passwordSaved);
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(t.newPasswordTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.newPassword),
                validator: (v) => (v == null || v.length < 8) ? t.passwordTooShort : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.confirmPassword),
                validator: (v) => v != _password.text ? t.passwordsDontMatch : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(t.savePassword),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
