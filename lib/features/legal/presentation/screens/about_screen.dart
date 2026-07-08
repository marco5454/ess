import 'package:flutter/material.dart';

import '../../../../core/legal/legal_text.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/chapel_theme.dart';

/// About / legal screen. Reachable from every AppBar (info icon) and from
/// the login screen footer.
///
/// This is the single canonical surface where users see the full
/// unaffiliation notice, personal-use scope, no-warranty clause, and
/// privacy note. All copy comes from [LegalText] so the same wording is
/// used in the README and LICENSE.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          const Center(child: _AboutHero()),
          const SizedBox(height: 28),
          _Section(
            title: 'Not affiliated with the Church',
            icon: Icons.info_outline,
            body: LegalText.unaffiliationFull,
          ),
          _Section(
            title: 'For personal use only',
            icon: Icons.person_outline,
            body: LegalText.personalUse,
          ),
          _Section(
            title: 'Data & privacy',
            icon: Icons.lock_outline,
            body: LegalText.privacy,
          ),
          _Section(
            title: 'No warranty',
            icon: Icons.gavel_outlined,
            body: LegalText.noWarranty,
          ),
          _Section(
            title: 'Support',
            icon: Icons.person_pin_outlined,
            body: LegalText.contact,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Bishopric Tracker · personal build',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ChapelPalette.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: ChapelPalette.navy,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Center(child: ChapelIcon(size: 40)),
        ),
        const SizedBox(height: 14),
        Text(
          'Bishopric Tracker',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: ChapelPalette.navyDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          LegalText.tagline,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ChapelPalette.inkSoft,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: ChapelPalette.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ChapelPalette.navyDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ChapelPalette.ink,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
