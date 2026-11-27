import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
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
      // Support chat tolerates more latency than ride dispatch does — widened
      // from 4s (found during a load-readiness audit: this was adding a fixed
      // per-open-conversation request rate with no corresponding urgency,
      // unlike the driver offer poll, which has a hard 25s expiry window).
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
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

  // Polls every 700ms (instead of the background 10s cadence) for up to
  // ~20s right after triggering an AI reply, through the same phone-
  // verified fetchMessages() path _refresh() already uses — no Realtime
  // involved, since support_messages deliberately has no direct SELECT
  // grant (it can hold PII/complaints across every user; see
  // support_chat_repository.dart's class doc comment). Stops as soon as
  // the newest message is a finished (non-streaming) AI reply, or after
  // the timeout, whichever comes first — a stuck/slow stream just falls
  // back to the normal 10s poll noticing it eventually, same as before
  // this feature existed.
  Future<void> _pollWhileStreaming() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await _refresh();
      if (_messages.isNotEmpty) {
        final last = _messages.last;
        if (last.senderRole == 'ai' && !last.streaming) return;
      }
      await Future.delayed(const Duration(milliseconds: 700));
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
        // ai-support-reply (supabase/functions/ai-support-reply) now writes
        // its reply incrementally as Anthropic streams it back, rather than
        // waiting for the whole thing — but sb.functions.invoke still only
        // resolves once the function itself returns, so the streaming only
        // becomes visible here if something keeps re-fetching the row while
        // that call is in flight. _pollWhileStreaming does that: a tight
        // poll (700ms) running concurrently with triggerAiReply, so the
        // reply visibly grows in instead of appearing all at once at the
        // end. The existing 10s background poll is untouched — this is
        // purely an extra, short-lived, faster poll layered on top while a
        // reply is actively being generated.
        unawaited(_repo.triggerAiReply(conversationId: id, phone: widget.myPhone));
        unawaited(_pollWhileStreaming());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('support_chat_send_error'))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('support_chat_appbar_title'))),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.tr('support_chat_empty_state'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textFaint),
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
                                        m.senderRole == 'ai' ? context.tr('support_chat_ai_label') : context.tr('support_chat_support_label'),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                                      ),
                                    ),
                                  RichText(
                                    text: TextSpan(
                                      style: TextStyle(color: isMine ? Colors.white : context.bodyText, fontSize: 14),
                                      children: [
                                        TextSpan(text: m.body),
                                        // Still streaming in — a trailing
                                        // cursor so an empty/short bubble
                                        // reads as "typing", not "empty".
                                        if (m.streaming) const TextSpan(text: ' ▌', style: TextStyle(color: AppColors.primary)),
                                      ],
                                    ),
                                  ),
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
                        hintText: context.tr('support_chat_input_hint'),
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
