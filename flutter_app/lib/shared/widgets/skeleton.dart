import 'package:flutter/material.dart';

/// A single shimmering placeholder block — the building piece for every
/// skeleton layout below. Pulses between two muted tones instead of
/// showing a blank gap or a spinner, so a loading page already reads as
/// "a list/grid of cards is about to appear here" rather than "nothing is
/// happening yet".
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2F2C) : const Color(0xFFE6E9E6);
    final highlight = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3A413D) : const Color(0xFFF2F4F2);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          color: Color.lerp(base, highlight, _controller.value),
        ),
      ),
    );
  }
}

/// One card's worth of placeholder — an image block over two text lines —
/// matching the `_ItemCard`/`_StoreCard` shape used across the app's
/// image+text grids and lists.
class SkeletonImageTextCard extends StatelessWidget {
  final double imageAspectRatio;
  const SkeletonImageTextCard({super.key, this.imageAspectRatio = 1.1});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: imageAspectRatio,
            child: const SkeletonBox(width: double.infinity, height: double.infinity, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: constraints.maxWidth * 0.7, height: 12),
          const SizedBox(height: 6),
          SkeletonBox(width: constraints.maxWidth * 0.4, height: 12),
        ],
      ),
    );
  }
}

/// A grid of [SkeletonImageTextCard]s, same geometry as the real
/// `GridView.builder` it stands in for — drop this in wherever a grid of
/// photo+text cards is still loading.
class SkeletonImageTextGrid extends StatelessWidget {
  final int crossAxisCount;
  final int itemCount;
  final double childAspectRatio;
  const SkeletonImageTextGrid({super.key, this.crossAxisCount = 2, this.itemCount = 6, this.childAspectRatio = 0.72});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, _) => const SkeletonImageTextCard(),
    );
  }
}

/// One row's worth of placeholder for a list tile with a leading photo —
/// matching a typical `ListTile`/product-row shape (thumbnail, title line,
/// subtitle line).
class SkeletonListRow extends StatelessWidget {
  const SkeletonListRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SkeletonBox(width: 56, height: 56, borderRadius: BorderRadius.all(Radius.circular(10))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: MediaQuery.of(context).size.width * 0.5, height: 13),
                const SizedBox(height: 8),
                SkeletonBox(width: MediaQuery.of(context).size.width * 0.3, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short column of [SkeletonListRow]s — drop this in wherever a photo
/// list is still loading.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  const SkeletonList({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (_, _) => const SkeletonListRow(),
    );
  }
}
