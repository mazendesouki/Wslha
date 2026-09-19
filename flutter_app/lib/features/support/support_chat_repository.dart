import '../../core/supabase_client.dart';

class SupportMessage {
  final String id;
  final String senderRole; // 'user' | 'support'
  final String body;
  final DateTime createdAt;
  const SupportMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  factory SupportMessage.fromRow(Map<String, dynamic> r) => SupportMessage(
        id: r['id'] as String,
        senderRole: r['sender_role'] as String,
        body: r['body'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}

/// Unlike ride_messages, support_messages carries no direct SELECT grant
/// (db/security-73) — support chats can contain personal complaints/PII
/// across every user, so a blanket RLS using(true) would let anyone with
/// the anon key dump every user's conversation, not just their own known
/// id. Every read/write goes through a phone-verified RPC instead, which
/// means no Realtime stream here — the screen polls get_support_messages
/// on a short timer while open.
class SupportChatRepository {
  Future<String> getOrCreateConversation(String phone) async {
    final id = await sb.rpc('get_or_create_support_conversation', params: {'p_phone': phone});
    return id as String;
  }

  Future<List<SupportMessage>> fetchMessages({required String conversationId, required String phone}) async {
    final rows = await sb.rpc('get_support_messages', params: {
      'p_conversation_id': conversationId,
      'p_phone': phone,
    });
    return (rows as List).cast<Map<String, dynamic>>().map(SupportMessage.fromRow).toList();
  }

  Future<void> send({required String conversationId, required String phone, required String body}) async {
    await sb.rpc('send_support_message', params: {
      'p_conversation_id': conversationId,
      'p_phone': phone,
      'p_body': body,
    });
  }

  /// Fires the Claude-powered auto-reply (supabase/functions/ai-support-reply).
  /// The function itself no-ops once a human admin has taken the
  /// conversation over (support_conversations.ai_enabled) or the
  /// feature_ai_bot_enabled flag is off — so it's safe to call
  /// unconditionally after every user message. Errors are swallowed: the
  /// worst case is just no auto-reply, same as a human support agent not
  /// answering instantly.
  Future<void> triggerAiReply({required String conversationId, required String phone}) async {
    try {
      await sb.functions.invoke('ai-support-reply', body: {
        'conversation_id': conversationId,
        'phone': phone,
      });
    } catch (_) {}
  }
}
