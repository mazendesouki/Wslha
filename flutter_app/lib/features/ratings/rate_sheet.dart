import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'ratings_repository.dart';

class RatingResult {
  final int rating;
  final List<String> tags;
  final String? comment;
  RatingResult({required this.rating, required this.tags, this.comment});
}

/// Single-target rating sheet (driver→customer or customer→driver) — an
/// emoji mood picker instead of stars, with tag chips that swap to a
/// positive or a constructive set depending on the mood picked, instead of
/// one static comment box. Returns null if the user dismisses/skips.
class RateSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> positiveTags;
  final List<String> negativeTags;

  const RateSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.positiveTags,
    required this.negativeTags,
  });

  static Future<RatingResult?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<String> positiveTags,
    required List<String> negativeTags,
  }) {
    return showModalBottomSheet<RatingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateSheet(title: title, subtitle: subtitle, positiveTags: positiveTags, negativeTags: negativeTags),
    );
  }

  @override
  State<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<RateSheet> {
  int? _mood; // 0..4 index into ratingEmojis
  final Set<String> _tags = {};
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  List<String> get _activeTags {
    if (_mood == null) return const [];
    if (_mood! >= 3) return widget.positiveTags;
    if (_mood! == 2) return [...widget.positiveTags.take(2), ...widget.negativeTags.take(2)];
    return widget.negativeTags;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(99))),
              ),
              const SizedBox(height: 16),
              Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text(widget.subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(ratingEmojis.length, (i) {
                  final selected = _mood == i;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _mood = i;
                      _tags.clear();
                    }),
                    child: AnimatedScale(
                      scale: selected ? 1.25 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primaryLight : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(ratingEmojis[i], style: const TextStyle(fontSize: 30)),
                          ),
                          if (selected) ...[
                            const SizedBox(height: 4),
                            Text(ratingLabels[i], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary)),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
              if (_mood != null) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('إيه اللي حصل بالظبط؟ (اختياري)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87)),
                ),
                const SizedBox(height: 10),
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
                      onSelected: (_) => setState(() {
                        selected ? _tags.remove(tag) : _tags.add(tag);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'تفاصيل إضافية (اختياري)'),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('تخطي'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () {
                          setState(() => _submitting = true);
                          Navigator.of(context).pop(RatingResult(
                            rating: _mood! + 1,
                            tags: _tags.toList(),
                            comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
                          ));
                        },
                        child: const Text('إرسال التقييم'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 20),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('تخطي دلوقتي')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
