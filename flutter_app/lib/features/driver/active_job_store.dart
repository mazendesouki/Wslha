import 'package:flutter/foundation.dart';

class QueuedJob {
  final String type; // 'ride' | 'order'
  final Map<String, dynamic> data;
  QueuedJob(this.type, this.data);
}

/// Single source of truth for "what job is the driver working on right
/// now" — shared between the home tab (offers/queue/progress buttons) and
/// the "طلباتي ورحلاتي" history screen. Opening an in-progress ride from
/// history used to run its own disconnected copy of this state, so
/// advancing it there never showed up on the home tab and vice versa —
/// both screens now read/write this singleton instead of keeping a local
/// copy, and it survives switching tabs since it isn't tied to either
/// screen's widget lifecycle.
class ActiveJobStore extends ChangeNotifier {
  ActiveJobStore._();
  static final ActiveJobStore instance = ActiveJobStore._();

  Map<String, dynamic>? job;
  String? jobType; // 'ride' | 'order'
  String rideStep = 'accepted'; // accepted -> arrived -> in_progress -> completed
  bool pickedUp = false; // orders only
  final List<QueuedJob> queue = [];

  void activate(String type, Map<String, dynamic> data, {String? rideStep}) {
    job = data;
    jobType = type;
    this.rideStep = rideStep ?? 'accepted';
    pickedUp = false;
    notifyListeners();
  }

  void enqueue(QueuedJob q) {
    queue.add(q);
    notifyListeners();
  }

  /// Puts the job currently active back at the front of the queue instead
  /// of dropping it — nothing accepted is ever lost.
  void switchToQueued(int index) {
    final next = queue.removeAt(index);
    if (job != null) {
      queue.insert(0, QueuedJob(jobType!, job!));
    }
    activate(next.type, next.data);
  }

  void setRideStep(String step) {
    rideStep = step;
    notifyListeners();
  }

  void setPickedUp(bool value) {
    pickedUp = value;
    notifyListeners();
  }

  void clearActive() {
    job = null;
    jobType = null;
    rideStep = 'accepted';
    pickedUp = false;
    notifyListeners();
  }

  void clearAll() {
    job = null;
    jobType = null;
    rideStep = 'accepted';
    pickedUp = false;
    queue.clear();
    notifyListeners();
  }
}
