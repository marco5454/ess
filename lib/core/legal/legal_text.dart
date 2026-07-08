/// Canonical disclaimer / legal copy for the app.
///
/// One source of truth for every user-visible legal surface (login footer,
/// About screen, README, LICENSE). If you change wording here, please also
/// update `README.md` and `LICENSE` in the repo root so they stay in sync.
class LegalText {
  const LegalText._();

  /// Short unaffiliation line shown as fine print on the login screen and
  /// wherever a compact notice is appropriate.
  static const String shortUnaffiliation =
      'A personal-use tool. Not affiliated with, endorsed by, or connected '
      'to The Church of Jesus Christ of Latter-day Saints.';

  /// Product tagline mirrored here so the About screen can render it
  /// without importing feature-level UI.
  static const String tagline = 'Members and callings, kept together';

  /// Full unaffiliation notice — expanded form used in the About screen
  /// and README. Includes the "descriptive use" wording so the LDS /
  /// "bishopric" terminology can't be mistaken for an endorsement.
  static const String unaffiliationFull =
      'Bishopric Tracker is an independent, personal-use application. It '
      'is not affiliated with, endorsed by, sponsored by, or connected to '
      'The Church of Jesus Christ of Latter-day Saints in any way. The '
      'terms "LDS", "bishopric", "ward", "calling", and similar '
      'ecclesiastical vocabulary are used descriptively to reference the '
      'user\'s own personal record-keeping context. All names, marks, and '
      'trademarks referenced here remain the property of their respective '
      'owners.';

  /// Personal-use scope wording. Makes explicit that this tool is a
  /// personal aide and not a substitute for official Church record-keeping
  /// systems.
  static const String personalUse =
      'This app is provided for a single user\'s personal organization '
      'only. It is not an official record-keeping system for any ward, '
      'branch, stake, or congregation. Do not use it as a replacement for '
      'the Church\'s official systems (LCR, ChurchofJesusChrist.org, etc.) '
      'or as an authoritative source for calling status, membership, or '
      'ecclesiastical decisions.';

  /// No-warranty clause. Kept in plain language on purpose — the LICENSE
  /// file contains the formal legal version.
  static const String noWarranty =
      'The software is provided "as is" without warranty of any kind, '
      'express or implied, including but not limited to warranties of '
      'merchantability, fitness for a particular purpose, and '
      'noninfringement. The author accepts no responsibility for data '
      'loss, sync failures, incorrect information, or any consequences '
      'arising from the use or inability to use this software. You use '
      'it at your own risk.';

  /// Privacy / data-handling note. Reflects the actual architecture:
  /// local Drift database on the device, syncing to a Supabase project the
  /// user themselves configured.
  static const String privacy =
      'Data you enter (member names, contact info, callings, notes) is '
      'stored locally on this device in an encrypted-at-rest SQLite '
      'database and synchronized to the Supabase project configured for '
      'this build. No data is sent to the author, to the Church, or to '
      'any third party beyond that Supabase instance. Because you are '
      'the operator of the Supabase project, you alone are responsible '
      'for handling that personal data in accordance with the privacy '
      'laws that apply to you (e.g. GDPR, CCPA, local statutes), and for '
      'obtaining any consent required from the individuals whose '
      'information you record.';

  /// Version-independent "how to report an issue" pointer. Kept generic
  /// so we can change hosting without editing this file.
  static const String contact =
      'This app is maintained by a single individual as a personal '
      'project. There is no support contract, service-level agreement, '
      'or guaranteed response time.';
}
