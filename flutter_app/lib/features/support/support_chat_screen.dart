import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/theme.dart';
import 'support_chat_repository.dart';

class SupportChatScreen extends StatefulWidget {
  final String myPhone;
  const SupportChatScreen({super.key, required this.myPhone});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _repo = SupportChatRepository();
  final _msgCtrl = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;
  String? _conversationId;
  List<SupportMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final id = await _repo.getOrCreateConversation(widget.myPhone);
      _conversationId = id;
      await _refresh();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } catch (_) {
      // Keep the loading spinner off and show the empty-state; the send
      // button still retries getOrCreateConversation on next attempt.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final id = _conversationId;
    if (id == null || !mounted) return;
    try {
      final rows = await _repo.fetchMessages(conversationId: id, phone: widget.myPhone);
      if (!mounted) return;
      final grew = rows.length > _messages.length;
      setState(() => _messages = rows);
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      // Transient network hiccup — next poll tick will retry.
    }
  }

  Future<void> _send() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      var id = _conversationId;
      id ??= await _repo.getOrCreateConversation(widget.myPhone);
      _conversationId = id;
      await _repo.send(conversationId: id, phone: widget.myPhone, body: body);
      await _refresh();
      if (FeatureFlags.aiBotEnabled) {
        // Fire-and-forget: refresh again once the bot (if it answers)
        // has had time to reply, without blocking the send button.
        unawaited(_repo.triggerAiReply(conversationId: id, phone: widget.myPhone).then((_) => _refresh()));
      }
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
      appBar: AppBar(title: const Text('💬 شات مباشر مع الدعم الفني')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'اكتب رسالتك وفريق الدعم هيرد عليك من هنا',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textFaint),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isMine = m.senderRole == 'user';
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
                                  if (!isMine)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        m.senderRole == 'ai' ? '🤖 مساعد آلي' : '🎧 الدعم الفني',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                                      ),
                                    ),
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
                        hintText: 'اكتب رسالتك للدعم الفني...',
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
