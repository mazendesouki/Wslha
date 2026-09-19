import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'ride_chat_repository.dart';

class RideChatScreen extends StatefulWidget {
  final String rideId;
  final String myPhone;
  final String myRole; // 'customer' | 'driver'
  final String otherPartyName;
  const RideChatScreen({
    super.key,
    required this.rideId,
    required this.myPhone,
    required this.myRole,
    required this.otherPartyName,
  });

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  final _repo = RideChatRepository();
  final _msgCtrl = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await _repo.send(rideId: widget.rideId, senderPhone: widget.myPhone, senderRole: widget.myRole, body: body);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إرسال الرسالة، حاول تاني')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text('💬 ${widget.otherPartyName}')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<RideMessage>>(
              stream: _repo.watch(widget.rideId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('ابدأ المحادثة — الرسايل هنا بس بين انت والطرف التاني في الرحلة دي', style: TextStyle(color: AppColors.textFaint)),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final isMine = m.senderPhone == widget.myPhone;
                    return Align(
                      alignment: isMine ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          color: isMine ? AppColors.primary : context.surfaceColor,
                          borderRadius: BorderRadius.circular(14),
                          border: isMine ? null : Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.body, style: TextStyle(color: isMine ? Colors.white : context.bodyText, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 10, color: isMine ? Colors.white70 : AppColors.textFaint),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.surfaceColor, border: Border(top: BorderSide(color: context.borderColor))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        filled: true,
                        fillColor: context.mutedSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
