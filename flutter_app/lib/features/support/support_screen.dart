import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/contact_launcher.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'support_chat_screen.dart';

// Same numbers/address contact.astro shows on the website — reusing them
// here instead of inventing separate app-only contact info.
const _supportPhone = '+201102667324';
const _supportEmail = 'info@wslha.co';

// Resolved per-locale at point of use (no BuildContext available at the
// top-level const declaration this list used to be).
List<(String, String)> _faq(BuildContext context) => [
      (context.tr('support_faq_cancel_ride_q'), context.tr('support_faq_cancel_ride_a')),
      (context.tr('support_faq_driver_late_q'), context.tr('support_faq_driver_late_a')),
      (context.tr('support_faq_wallet_topup_q'), context.tr('support_faq_wallet_topup_a')),
      (context.tr('support_faq_forgot_item_q'), context.tr('support_faq_forgot_item_a')),
      (context.tr('support_faq_become_driver_merchant_q'), context.tr('support_faq_become_driver_merchant_a')),
      (context.tr('support_faq_price_difference_q'), context.tr('support_faq_price_difference_a')),
    ];

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _openChat(BuildContext context) async {
    final session = await SessionStore.load();
    if (session == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportChatScreen(myPhone: session.phone)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('support_appbar_title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SectionHeader(context.tr('support_section_contact_us')),
          if (FeatureFlags.supportChatEnabled && FeatureFlags.aiBotEnabled)
            _ContactTile(
              icon: '🤖',
              title: context.tr('support_ai_assistant_title'),
              subtitle: context.tr('support_ai_assistant_subtitle'),
              onTap: () => _openChat(context),
            ),
          if (FeatureFlags.supportChatEnabled)
            _ContactTile(
              icon: '🎧',
              title: context.tr('support_live_chat_title'),
              subtitle: context.tr('support_live_chat_subtitle'),
              onTap: () => _openChat(context),
            ),
          _ContactTile(
            icon: '📞',
            title: context.tr('support_call_us_title'),
            subtitle: _supportPhone,
            onTap: () => callPhone(_supportPhone),
          ),
          _ContactTile(
            icon: '💬',
            title: context.tr('support_whatsapp_title'),
            subtitle: context.tr('support_whatsapp_subtitle'),
            onTap: () => openWhatsApp(_supportPhone),
          ),
          _ContactTile(
            icon: '✉️',
            title: context.tr('support_email_title'),
            subtitle: _supportEmail,
            onTap: () => launchUrl(Uri.parse('mailto:$_supportEmail')),
          ),
          const Divider(height: 24),
          _SectionHeader(context.tr('support_section_faq')),
          ..._faq(context).map((qa) => _FaqTile(question: qa.$1, answer: qa.$2)),
          const Divider(height: 24),
          _SectionHeader(context.tr('support_section_legal_links')),
          _ContactTile(
            icon: '📄',
            title: context.tr('support_terms_title'),
            onTap: () => launchUrl(Uri.parse('https://wslha.co/terms'), mode: LaunchMode.externalApplication),
          ),
          _ContactTile(
            icon: '🔒',
            title: context.tr('support_privacy_title'),
            onTap: () => launchUrl(Uri.parse('https://wslha.co/privacy'), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.textFaint),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final String icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _ContactTile({required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 20)),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!, textDirection: TextDirection.ltr),
      trailing: const Icon(Icons.chevron_left),
      onTap: onTap,
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer, style: const TextStyle(fontSize: 13, color: AppColors.textFaint)),
      ],
    );
  }
}
