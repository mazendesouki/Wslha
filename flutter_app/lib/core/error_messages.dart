/// Whether [e] looks like a transient connectivity failure (dropped wifi,
/// a DNS blip, a connection reset mid-request) rather than a real
/// application/server error.
///
/// Reported live: a driver tapping "متصل" (go online) got
/// `ClientException with SocketException: Software caused connection
/// abort ... uri=https://.../rest/v1/rpc/upsert_driver_location` dumped
/// straight into a SnackBar — alarming and meaningless to a non-technical
/// user, for a failure that's almost always transient and resolves on its
/// own or on retry. The exact same raw-dump pattern exists on the
/// customer app's own most-used action (submitting a ride, rides_screen.dart).
///
/// Call sites should show `context.tr('network_error_friendly')` instead of
/// the raw `'$e'` when this returns true, and keep the existing raw-message
/// fallback for every other (genuinely unexpected) error.
bool isConnectivityError(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Connection closed') ||
      s.contains('Connection reset') ||
      s.contains('Failed host lookup') ||
      s.contains('TimeoutException') ||
      s.contains('Software caused connection abort');
}

/// One retry after a short delay for a transient connection error — the
/// shared version of the retry originally written inline in
/// driver_repository.dart's goOnline()/pingLocation(). Any repository call
/// on a critical single-shot action (submitting an order, accepting/
/// rejecting one, going online) should go through this instead of calling
/// the network directly, so a dropped/reset socket gets one more chance
/// before the user sees a failure at all. Only retries connectivity-class
/// errors; anything else (an RLS denial, a real server/validation error)
/// rethrows immediately so it isn't masked by a pointless retry.
Future<T> withConnectivityRetry<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (!isConnectivityError(e)) rethrow;
    await Future.delayed(const Duration(milliseconds: 800));
    return action();
  }
}
