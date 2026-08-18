import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'ratings_repository.dart';

class OrderRatingResult {
  final int storeRating;
  final int? driverRating;
  final List<String> tags;
  final String? comment;
  OrderRatingResult({required this.storeRating, this.driverRating, required this.tags, this.comment});
}

/// Combined store+driver rating for a delivery order — same two-target
/// shape track.astro's rate-card uses (store mood is required, driver mood
/// only shown/asked when a driver was actually assigned), in one sheet
/// instead of two separate prompts.
class OrderRatingSheet extends StatefulWidget {
  final String storeName;
  final bool hasDriver;

  const OrderRatingSheet({super.key, required this.storeName, required this.hasDriver});

  static Future<OrderRatingResult?> show(BuildContext context, {required String storeName, required bool hasDriver}) {
    return showModalBottomSheet<OrderRatingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderRatingSheet(storeName: storeName, hasDriver: hasDriver),
    );
  }

  @override
  State<OrderRatingSheet> createState() => _OrderRatingSheetState();
}

class _OrderRatingSheetState extends State<OrderRatingSheet> {
  int? _storeMood;
  int? _driverMood;
  final Set<String> _tags = {};
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  List<String> get _activeTags {
    if (_storeMood == null) return const [];
    return _storeMood! >= 3 ? positiveStoreTags : negativeStoreTags;
  }

  Widget _moodRow(String label, int? selected, ValueChanged<int> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(ratingEmojis.length, (i) {
            final isSel = selected == i;
            return GestureDetector(
              onTap: () => onPick(i),
              child: AnimatedScale(
                scale: isSel ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: isSel ? AppColors.primaryLight : Colors.transparent, shape: BoxShape.circle),
                  child: Text(ratingEmojis[i], style: const TextStyle(fontSize: 26)),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 16),
              const Text('قيّم طلبك', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 18),
              _moodRow('${widget.storeName} 🏪', _storeMood, (i) => setState(() {
                    _storeMood = i;
                    _tags.clear();
                  })),
              if (widget.hasDriver) ...[
                const SizedBox(height: 18),
                _moodRow('السائق 🚖', _driverMood, (i) => setState(() => _driverMood = i)),
              ],
              if (_activeTags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _activeTags.map((tag) {
                    final selected = _tags.contains(tag);
                    return ChoiceChip(
                      label: Text(tag, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.black87)),
                      selected: selected,
                      selectedColor: AppColors.primary,
                      backgroundColor: const Color(0xFFF3F4F6),
                      onSelected: (_) => setState(() => selected ? _tags.remove(tag) : _tags.add(tag)),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 14),
              TextField(controller: _commentCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'تعليق (اختياري)')),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('تخطي'))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _storeMood == null
                          ? null
                          : () => Navigator.of(context).pop(OrderRatingResult(
                                storeRating: _storeMood! + 1,
                                driverRating: _driverMood == null ? null : _driverMood! + 1,
                                tags: _tags.toList(),
                                comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
                              )),
                      child: const Text('إرسال التقييم'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
