import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/contact_launcher.dart';
import '../../core/feature_flags.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'support_chat_screen.dart';

// Same numbers/address contact.astro shows on the website — reusing them
// here instead of inventing separate app-only contact info.
const _supportPhone = '+201102667324';
const _supportEmail = 'info@wslha.co';

const List<(String, String)> _faq = [
  ('إزاي ألغي مشوار بعد ما أحجزه؟', 'من شاشة تتبّع المشوار فيه زرار "إلغاء" متاح طول ما السائق لسه ما بدأش الرحلة الفعلية.'),
  ('السائق اتأخر، هل هيتحاسب؟', 'أيوه، لو السائق اتأخر عن الميعاد بيتحصّل عليه خصم تلقائي عن كل دقيقة تأخير زيادة عن فترة السماح.'),
  ('إزاي أضيف رصيد للمحفظة؟', 'من شاشة "المحفظة" اختار "إضافة رصيد" واختار طريقة الدفع اللي تناسبك (فودافون كاش / إنستاباي / تحويل بنكي).'),
  ('نسيت حاجة في العربية، أعمل إيه؟', 'تواصل مع السائق مباشرة من شاشة تفاصيل المشوار (اتصال/واتساب)، أو كلّمنا على الدعم وهنساعدك توصله.'),
  ('إزاي أبقى سائق أو تاجر على وصّلها؟', 'من شاشة التسجيل اختار "سائق" أو "تاجر" بدل "عميل"، واملأ البيانات المطلوبة — طلبك بيتراجع خلال 24-48 ساعة.'),
  ('السعر اللي ظهرلي مختلف عن اللي اتحصّل فعليًا، ليه؟', 'السعر المبدئي تقديري حسب المسافة؛ ممكن يتغيّر لو فيه انتظار زيادة عن المسموح أو توقف إضافي أثناء الرحلة — التفاصيل موجودة في فاتورة المشوار.'),
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
      appBar: AppBar(title: const Text('المساعدة والدعم')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const _SectionHeader('تواصل معنا'),
          if (FeatureFlags.supportChatEnabled)
            _ContactTile(
              icon: '🎧',
              title: 'شات مباشر مع الدعم الفني',
              subtitle: 'رد سريع من فريقنا داخل التطبيق',
              onTap: () => _openChat(context),
            ),
          _ContactTile(
            icon: '📞',
            title: 'اتصل بنا',
            subtitle: _supportPhone,
            onTap: () => callPhone(_supportPhone),
          ),
          _ContactTile(
            icon: '💬',
            title: 'واتساب',
            subtitle: 'راسلنا على واتساب',
            onTap: () => openWhatsApp(_supportPhone),
          ),
          _ContactTile(
            icon: '✉️',
            title: 'إيميل',
            subtitle: _supportEmail,
            onTap: () => launchUrl(Uri.parse('mailto:$_supportEmail')),
          ),
          const Divider(height: 24),
          const _SectionHeader('أسئلة شائعة'),
          ..._faq.map((qa) => _FaqTile(question: qa.$1, answer: qa.$2)),
          const Divider(height: 24),
          const _SectionHeader('روابط قانونية'),
          _ContactTile(
            icon: '📄',
            title: 'الشروط والأحكام',
            onTap: () => launchUrl(Uri.parse('https://wslha.co/terms'), mode: LaunchMode.externalApplication),
          ),
          _ContactTile(
            icon: '🔒',
            title: 'سياسة الخصوصية',
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
