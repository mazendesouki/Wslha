import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'emergency_contacts_repository.dart';

/// Reachable from الإعدادات — up to 3 contacts (db/security-68's cap) who
/// receive an SMS with live location + ride-tracking link when the زرار
/// طوارئ (SosButton) is triggered.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _repo = EmergencyContactsRepository();
  UserSession? _session;
  List<EmergencyContact>? _contacts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) return;
    final contacts = await _repo.list(session.phone).catchError((_) => <EmergencyContact>[]);
    if (!mounted) return;
    setState(() {
      _session = session;
      _contacts = contacts;
    });
  }

  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('emergency_add_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: context.tr('emergency_name_label'), prefixIcon: const Icon(Icons.person_outline))),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: context.tr('emergency_phone_label'), hintText: '01xxxxxxxxx', prefixIcon: const Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final rawPhone = phoneCtrl.text.trim();
                if (name.isEmpty || !isEgyptianMobile(rawPhone)) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text(context.tr('emergency_validation_error'))),
                  );
                  return;
                }
                Navigator.of(sheetContext).pop(true);
              },
              child: Text(context.tr('emergency_save')),
            ),
          ],
        ),
      ),
    );
    if (added != true || _session == null) return;
    final normalized = normalizeEgyptianPhone(phoneCtrl.text.trim());
    setState(() => _saving = true);
    final ok = await _repo.add(_session!.phone, nameCtrl.text.trim(), normalized);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('emergency_max_contacts'))));
      return;
    }
    await _load();
  }

  Future<void> _deleteContact(EmergencyContact c) async {
    if (_session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('emergency_delete_title')),
        content: Text('${context.tr('emergency_delete_body_prefix')} "${c.name}" ${context.tr('emergency_delete_body_suffix')}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('emergency_cancel'))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(context.tr('emergency_delete'), style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.delete(c.id, _session!.phone);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text('🆘 ${context.tr('emergency_appbar_title')}')),
      body: contacts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Text(
                    context.tr('emergency_safety_notice'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                if (contacts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(16)),
                    child: const Center(
                      child: Text(context.tr('emergency_empty'), style: const TextStyle(color: AppColors.textFaint)),
                    ),
                  )
                else
                  ...contacts.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.borderColor)),
                        child: Row(
                          children: [
                            const CircleAvatar(backgroundColor: AppColors.primaryLight, child: Icon(Icons.person, color: AppColors.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                  Text(c.phone, style: const TextStyle(fontSize: 12, color: AppColors.textFaint), textDirection: TextDirection.ltr),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deleteContact(c),
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 10),
                if (contacts.length < 3)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _addContact,
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('emergency_add_button')),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
              ],
            ),
    );
  }
}
