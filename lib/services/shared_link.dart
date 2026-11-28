import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dentpass/config.dart';
import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// Slot links shared on WhatsApp: ".../dentpass/?slot=<id>".
/// The slot is remembered across sign-up (and an email confirmation) and opened once the person is in.
class SharedLink {
  static const _key = 'shared_slot_v1';
  static final _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');
  static String? _slotId;

  static String? get slotId => _slotId;

  /// Reads the link the app was opened with. Call before the address bar is cleaned.
  static Future<void> capture() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromUrl = Uri.base.queryParameters['slot'];
      if (fromUrl != null && _uuid.hasMatch(fromUrl)) {
        _slotId = fromUrl;
        await prefs.setString(_key, fromUrl);
      } else {
        _slotId = prefs.getString(_key);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _slotId = null;
    try {
      (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }

  static Uri linkFor(String slotId) => Uri.parse(AppConfig.siteUrl).replace(queryParameters: {'slot': slotId});
}

/// The message that goes with a shared slot.
String shareText(BuildContext context, Slot slot) {
  final t = AppLocalizations.of(context);
  return [
    '${kindName(t, slot.kind)}: ${slot.title}',
    '${whenText(context, slot.startsAt, slot.endsAt)} · ${areaName(context, slot.area)}',
    priceText(context, slot.priceEgp) + (slot.negotiable ? ' (${t.negotiable})' : ''),
    if (slot.hostName.isNotEmpty) slot.hostName,
    '${t.shareBookOn} ${SharedLink.linkFor(slot.id)}',
  ].join('\n');
}

/// WhatsApp (pick a chat or group) or copy the link.
Future<void> shareSlot(BuildContext context, Slot slot) async {
  final t = AppLocalizations.of(context);
  final text = shareText(context, slot);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(t.shareTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        ListTile(
          leading: const Icon(Icons.chat_outlined),
          title: Text(t.shareWhatsApp),
          subtitle: Text(t.shareWhatsAppHint),
          onTap: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
          },
        ),
        ListTile(
          leading: const Icon(Icons.link_rounded),
          title: Text(t.copyLink),
          onTap: () async {
            Navigator.pop(ctx);
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) showMessage(context, t.copied);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}
