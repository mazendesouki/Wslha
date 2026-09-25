import 'package:flutter/material.dart';
import '../../core/contact_launcher.dart';
import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';

class MarketplaceItemScreen extends StatefulWidget {
  final String itemId;
  const MarketplaceItemScreen({super.key, required this.itemId});

  @override
  State<MarketplaceItemScreen> createState() => _MarketplaceItemScreenState();
}

class _MarketplaceItemScreenState extends State<MarketplaceItemScreen> {
  final _repo = MarketplaceRepository();
  MarketItem? _item;
  bool _loading = true;
  bool _notFound = false;
  bool _viewCounted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final item = await _repo.fetchItem(widget.itemId);
    if (!mounted) return;
    setState(() {
      _item = item;
      _notFound = item == null;
      _loading = false;
    });
    if (item != null && !_viewCounted) {
      _viewCounted = true;
      _repo.incrementViews(item.id, item.views);
    }
  }

  Future<void> _openDeliverySheet(MarketItem item) async {
    final session = await SessionStore.load();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeliveryRequestSheet(item: item, session: session, repo: _repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('marketplace_item_title'))),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound || item == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔍', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text(context.tr('marketplace_item_not_found'), style: const TextStyle(color: AppColors.textFaint)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Gallery(images: item.images, title: item.title),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _badge(marketplaceConditions[item.condition] ?? item.condition, AppColors.primary),
                        if (item.sellerType == 'merchant') _badge('🏪 ${context.tr('marketplace_item_merchant_seller')}', AppColors.success),
                        if (item.status == 'sold') _badge(context.tr('marketplace_item_sold_badge'), AppColors.error),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 6),
                    Text('${item.price.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.success)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metaChip(context, '📍 ${item.city ?? item.area ?? context.tr('marketplace_item_default_city')}'),
                        _metaChip(context, '👁️ ${item.views} ${context.tr('marketplace_item_views_suffix')}'),
                        if (item.createdAt != null) _metaChip(context, '🗓️ ${_formatDate(item.createdAt!)}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      item.description?.isNotEmpty == true ? item.description! : context.tr('marketplace_item_no_description'),
                      style: const TextStyle(fontSize: 13, color: AppColors.textFaint, height: 1.7),
                    ),
                    const SizedBox(height: 20),
                    _SideCard(
                      icon: '📞',
                      title: context.tr('marketplace_item_contact_seller_title'),
                      subtitle: context.tr('marketplace_item_contact_seller_subtitle'),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => callPhone(item.contactPhone),
                              icon: const Icon(Icons.call, size: 18),
                              label: Text(context.tr('marketplace_item_call_button')),
                            ),
                          ),
                          if (item.whatsapp) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => openWhatsApp(item.contactPhone),
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                                icon: const Icon(Icons.chat, size: 18),
                                label: Text(context.tr('marketplace_item_whatsapp_button')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.status == 'active') ...[
                      const SizedBox(height: 12),
                      _SideCard(
                        icon: '🚚',
                        title: context.tr('marketplace_item_delivery_title'),
                        subtitle: context.tr('marketplace_item_delivery_subtitle'),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _openDeliverySheet(item),
                            icon: const Icon(Icons.local_shipping_outlined, size: 18),
                            label: Text(context.tr('marketplace_item_delivery_button')),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      );

  Widget _metaChip(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: context.mutedSurface, border: Border.all(color: context.borderColor), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
      );

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
}

class _Gallery extends StatefulWidget {
  final List<String> images;
  final String title;
  const _Gallery({required this.images, required this.title});

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(color: context.mutedSurface, borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text('📦', style: TextStyle(fontSize: 56))),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.images.length,
              itemBuilder: (_, i) => Image.network(
                widget.images[i],
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(color: context.mutedSurface, child: const Center(child: Text('📦', style: TextStyle(fontSize: 56)))),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.images.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 9 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? Colors.white : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget child;
  const _SideCard({required this.icon, required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(11)),
                child: Text(icon, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DeliveryRequestSheet extends StatefulWidget {
  final MarketItem item;
  final UserSession? session;
  final MarketplaceRepository repo;
  const _DeliveryRequestSheet({required this.item, required this.session, required this.repo});

  @override
  State<_DeliveryRequestSheet> createState() => _DeliveryRequestSheetState();
}

class _DeliveryRequestSheetState extends State<_DeliveryRequestSheet> {
  late final _nameCtrl = TextEditingController(text: widget.session?.name ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.session?.phone ?? '');
  final _addressCtrl = TextEditingController();
  String? _shipmentType;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = context.tr('marketplace_delivery_error_name'));
      return;
    }
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    if (address.length < 5) {
      setState(() => _error = context.tr('marketplace_delivery_error_address'));
      return;
    }
    if (_shipmentType == null) {
      setState(() => _error = context.tr('marketplace_delivery_error_shipment_type'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await widget.repo.requestDelivery(
      itemId: widget.item.id,
      buyerPhone: phone,
      buyerName: name,
      buyerAddress: address,
      shipmentType: _shipmentType,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('marketplace_delivery_success'))),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = context.tr('marketplace_delivery_error_generic');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(color: context.surfaceColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(999))),
            ),
            Text(context.tr('marketplace_delivery_sheet_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '${context.tr('marketplace_delivery_fee_prefix')} 25 ${context.tr('marketplace_delivery_fee_suffix')}',
              style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
              const SizedBox(height: 12),
            ],
            Text(context.tr('marketplace_delivery_shipment_type_label'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in marketplaceShipmentTypes)
                  ChoiceChip(
                    label: Text('${t.emoji} ${t.label}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _shipmentType == t.id ? Colors.white : context.bodyText)),
                    selected: _shipmentType == t.id,
                    selectedColor: AppColors.primary,
                    backgroundColor: context.mutedSurface,
                    side: BorderSide(color: _shipmentType == t.id ? AppColors.primary : context.borderColor),
                    onSelected: (_) => setState(() => _shipmentType = t.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: context.tr('marketplace_delivery_name_label'))),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('marketplace_delivery_phone_label'))),
            const SizedBox(height: 10),
            TextField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: InputDecoration(labelText: context.tr('marketplace_delivery_address_label')),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.tr('marketplace_item_delivery_button')),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
