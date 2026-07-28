import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import 'driver_repository.dart';

class DriverHomeScreen extends StatefulWidget {
  final UserSession session;
  const DriverHomeScreen({super.key, required this.session});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _repo = DriverRepository();
  Timer? _pollTimer;

  bool _online = false;
  bool _busy = false;
  PendingOffer? _offer;
  Map<String, dynamic>? _activeJob;
  String? _activeJobType; // 'ride' | 'order'
  bool _pickedUp = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_online || _activeJob != null || _offer != null) return;
      final offer = await _repo.getPendingOffer(widget.session.phone);
      if (offer != null && mounted) setState(() => _offer = offer);
    });
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _busy = true);
    if (value) {
      final ok = await _repo.goOnline(widget.session.phone, widget.session.name);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('محتاجين إذن الموقع عشان تظهر للطلبات القريبة')),
        );
      }
      setState(() {
        _online = ok;
        _busy = false;
      });
      if (ok) _startPolling();
    } else {
      await _repo.goOffline(widget.session.phone);
      _pollTimer?.cancel();
      setState(() {
        _online = false;
        _busy = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_offer == null) return;
    setState(() => _busy = true);
    final ok = await _repo.acceptOffer(_offer!.offerId, widget.session.phone, widget.session.name);
    setState(() {
      _busy = false;
      if (ok) {
        _activeJob = _offer!.data;
        _activeJobType = _offer!.targetType;
        _pickedUp = false;
      }
      _offer = null;
    });
  }

  Future<void> _reject() async {
    if (_offer == null) return;
    setState(() => _busy = true);
    await _repo.rejectOffer(_offer!.offerId, widget.session.phone);
    setState(() {
      _busy = false;
      _offer = null;
    });
  }

  Future<void> _advanceJob() async {
    final job = _activeJob;
    if (job == null) return;
    setState(() => _busy = true);
    if (_activeJobType == 'order') {
      final orderId = job['id'].toString();
      if (!_pickedUp) {
        await _repo.markOrderPickedUp(orderId);
        setState(() {
          _pickedUp = true;
          _busy = false;
        });
        return;
      }
      await _repo.confirmOrderDelivery(orderId, widget.session.phone);
    } else {
      await _repo.completeRide(job['id'].toString());
    }
    setState(() {
      _activeJob = null;
      _activeJobType = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('وصّلها سائق'),
        actions: const [LogoutButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _online ? const Color(0xFFF0FDF4) : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(_online ? Icons.check_circle : Icons.pause_circle, color: _online ? AppColors.success : AppColors.textFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _online ? 'متصل — بتستقبل طلبات' : 'غير متصل',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Switch(
                      value: _online,
                      onChanged: _busy || _activeJob != null ? null : _toggleOnline,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _activeJob != null
                    ? _buildActiveJob()
                    : _offer != null
                        ? _buildOfferCard()
                        : Center(
                            child: Text(
                              _online ? 'بنستنى طلب مناسب...' : 'اضغط "متصل" عشان تبدأ تستقبل طلبات',
                              style: const TextStyle(color: AppColors.textFaint),
                              textAlign: TextAlign.center,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferCard() {
    final data = _offer!.data;
    final isOrder = _offer!.targetType == 'order';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Text(isOrder ? '📦 طلب جديد' : '🚖 مشوار جديد', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                isOrder
                    ? '${data['store_name'] ?? ''} ← ${data['address'] ?? data['area'] ?? ''}'
                    : '${data['from_area'] ?? ''} ← ${data['to_area'] ?? ''}',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('${data['fare'] ?? data['total'] ?? data['delivery_fee'] ?? ''} ج.م', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _reject,
                child: const Text('رفض'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _accept,
                child: const Text('قبول'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveJob() {
    final job = _activeJob!;
    final isOrder = _activeJobType == 'order';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Text(isOrder ? '📦 طلب قيد التنفيذ' : '🚖 مشوار قيد التنفيذ', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                isOrder
                    ? '${job['store_name'] ?? ''} ← ${job['address'] ?? job['area'] ?? ''}'
                    : '${job['from_area'] ?? ''} ← ${job['to_area'] ?? ''}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _advanceJob,
          child: Text(isOrder ? (_pickedUp ? 'تم التسليم' : 'تم الاستلام من المتجر') : 'إنهاء الرحلة'),
        ),
      ],
    );
  }
}
