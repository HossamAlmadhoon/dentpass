import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';

class KindStyle {
  const KindStyle(this.tint, this.ink, this.icon);
  final Color tint;
  final Color ink;
  final IconData icon;
}

KindStyle kindStyle(SlotKind k) => switch (k) {
      SlotKind.observe => const KindStyle(AppColors.nileTint, AppColors.nile, Icons.visibility_outlined),
      SlotKind.course => const KindStyle(AppColors.nileTint, AppColors.nile, Icons.school_outlined),
      SlotKind.rent => const KindStyle(AppColors.blueTint, AppColors.blue, Icons.chair_outlined),
      SlotKind.cover => const KindStyle(AppColors.amberTint, AppColors.amber, Icons.swap_horiz),
    };

String kindName(AppLocalizations t, SlotKind k) => switch (k) {
      SlotKind.observe => t.kindObserve,
      SlotKind.course => t.kindCourse,
      SlotKind.rent => t.kindRent,
      SlotKind.cover => t.kindCover,
    };

String kindLine(AppLocalizations t, SlotKind k) => switch (k) {
      SlotKind.observe => t.kindObserveLine,
      SlotKind.course => t.kindCourseLine,
      SlotKind.rent => t.kindRentLine,
      SlotKind.cover => t.kindCoverLine,
    };

String actionLabel(AppLocalizations t, SlotKind k) => switch (k) {
      SlotKind.observe || SlotKind.course => t.actionBookSeat,
      SlotKind.rent => t.actionBookChair,
      SlotKind.cover => t.actionOfferCover,
    };

String roleName(AppLocalizations t, MemberRole r) =>
    r == MemberRole.dentist ? t.roleDentist : t.roleAssistant;

String statusName(AppLocalizations t, BookingStatus s) => switch (s) {
      BookingStatus.pending => t.statusPending,
      BookingStatus.accepted => t.statusAccepted,
      BookingStatus.declined => t.statusDeclined,
      BookingStatus.cancelled => t.statusCancelled,
    };
