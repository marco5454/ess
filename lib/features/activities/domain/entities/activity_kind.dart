import 'package:flutter/material.dart';

/// Well-known kinds of tracked activity.
///
/// Stored as freeform text in the database (`tracked_activities.kind`), so
/// this enum is *not* authoritative — it just backs the picker UI and the
/// label/icon lookup. Unknown values (from a future app version or manual
/// server edit) map to [ActivityKind.other].
///
/// Wire values are snake_case to match the SQL/HTTP conventions elsewhere.
enum ActivityKind {
  templeRecommend,
  ministeringInterview,
  youthInterview,
  tithingSettlement,
  followUp,
  other;

  /// The exact string persisted in `tracked_activities.kind`.
  String get wireName => switch (this) {
        ActivityKind.templeRecommend => 'temple_recommend',
        ActivityKind.ministeringInterview => 'ministering_interview',
        ActivityKind.youthInterview => 'youth_interview',
        ActivityKind.tithingSettlement => 'tithing_settlement',
        ActivityKind.followUp => 'follow_up',
        ActivityKind.other => 'other',
      };

  /// Human-friendly label for buttons, chips, and headers.
  String get label => switch (this) {
        ActivityKind.templeRecommend => 'Temple recommend',
        ActivityKind.ministeringInterview => 'Ministering interview',
        ActivityKind.youthInterview => 'Youth interview',
        ActivityKind.tithingSettlement => 'Tithing settlement',
        ActivityKind.followUp => 'Follow-up',
        ActivityKind.other => 'Other',
      };

  /// Compact icon used in list rows and filter chips.
  IconData get icon => switch (this) {
        ActivityKind.templeRecommend => Icons.temple_buddhist_outlined,
        ActivityKind.ministeringInterview => Icons.volunteer_activism_outlined,
        ActivityKind.youthInterview => Icons.emoji_people_outlined,
        ActivityKind.tithingSettlement => Icons.account_balance_wallet_outlined,
        ActivityKind.followUp => Icons.follow_the_signs_outlined,
        ActivityKind.other => Icons.checklist_outlined,
      };

  /// Parse the persisted string. Unknown values are mapped to
  /// [ActivityKind.other] rather than throwing — this table is meant to
  /// hold arbitrary categories, and forcing a hard error on an unknown
  /// kind would make new categories require a client update.
  static ActivityKind fromWire(String value) {
    return switch (value) {
      'temple_recommend' => ActivityKind.templeRecommend,
      'ministering_interview' => ActivityKind.ministeringInterview,
      'youth_interview' => ActivityKind.youthInterview,
      'tithing_settlement' => ActivityKind.tithingSettlement,
      'follow_up' => ActivityKind.followUp,
      _ => ActivityKind.other,
    };
  }
}
