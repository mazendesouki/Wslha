import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'driver_repository.dart';

/// Open negotiable ride requests nearby — a driver browses and submits
/// their own price on any of them, instead of waiting for a fixed-fare
/// dispatch offer. Reachable from an AppBar action on driver_home_screen.
/// See db/security-35-ride-price-negotiation.sql for the RPCs behind this.
class NegotiationScreen extends StatefulWidget {
  final UserSession session;
  const NegotiationScreen({super.key, required this.session});

  @override
  State<NegotiationScreen> createState() => _NegotiationScreenState();
}

class _NegotiationScreenState extends State<NegotiationScreen> {
  final _repo = DriverRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('🤝 طلبات تفاوض قريبة')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.watchOpenNegotiableRides(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rides = snapshot.data!
              .where((r) => r['status'] == 'pending' && (r['driver_phone'] == null || (r['driver_phone'] as String).isEmpty))
              .toList();

          if (rides.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'مفيش طلبات تفاوضية مفتوحة دلوقتي — هتظهر هنا أول ما عميل يطلب بسعر تفاوضي',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontWeight: FontWeight.w700),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _NegotiableRideCard(repo: _repo, ride: rides[i], session: widget.session),
          );
        },
      ),
    );
  }
}

class _NegotiableRideCard extends StatefulWidget {
  final DriverRepository repo;
  final Map<String, dynamic> ride;
  final UserSession session;
  const _NegotiableRideCard({required this.repo, required this.ride, required this.session});

  @override
  State<_NegotiableRideCard> createState() => _NegotiableRideCardState();
}

class _NegotiableRideCardState extends State<_NegotiableRideCard> {
  final _priceCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = num.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب سعر صحيح')));
      return;
    }
    setState(() => _submitting = true);
    final error = await widget.repo.submitPriceOffer(
      widget.ride['id'].toString(),
      widget.session.phone,
      widget.session.name,
      price,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '✅ اتبعت عرضك، هيوصل للعميل فورًا')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final refFare = ride['fare'];
    final distanceKm = (ride['distance_km'] as num?)?.toStringAsFixed(1);
    final etaMinutes = ride['eta_minutes'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.trip_origin, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('${ride['from_area'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(right: 6, top: 2, bottom: 2),
            child: SizedBox(height: 12, child: VerticalDivider(width: 1, thickness: 1.5, color: AppColors.textFaint)),
          ),
          Row(
            children: [
              const Icon(Icons.place, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(child: Text('${ride['to_area'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (distanceKm != null) _chip('📏 $distanceKm كم'),
              if (etaMinutes != null) _chip('🕐 $etaMinutes د'),
              if (refFare != null) _chip('💡 سعر تقديري: $refFare ج.م'),
            ],
          ),
          const SizedBox(height: 12),
          // Shows whether this driver already bid on this specific ride, so
          // they can adjust their price instead of thinking they never bid.
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.repo.watchOffersOnRide(ride['id'].toString()),
            builder: (context, snap) {
              final mine = (snap.data ?? [])
                  .where((o) => o['status'] == 'pending' && o['driver_phone'] == widget.session.phone)
                  .toList();
              final myPrice = mine.isNotEmpty ? (mine.first['offered_price'] as num?)?.toStringAsFixed(0) : null;
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: myPrice != null ? 'عرضك الحالي: $myPrice ج.م' : 'سعرك (ج.م)',
                        suffixText: 'ج.م',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(myPrice != null ? 'عدّل' : 'قدّم عرضي'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
    );
  }
}
