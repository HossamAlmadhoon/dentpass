import 'package:flutter/material.dart';

import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/profile_screen.dart';
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
  bool _signUp = false;
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
