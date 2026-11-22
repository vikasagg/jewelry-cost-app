import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../swarn/swarn_os.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Price Calculator → Fetch Price: type a tag number and get the price of
/// that piece from Swarn-OS, the shop's jewellery inventory system, at
/// today's approved rate.
class FetchPriceScreen extends StatefulWidget {
  const FetchPriceScreen({super.key});

  @override
  State<FetchPriceScreen> createState() => _FetchPriceScreenState();
}

class _FetchPriceScreenState extends State<FetchPriceScreen> {
  final _tag = TextEditingController();
  bool _busy = false;
  String? _error;
  SwarnItem? _item;

  SwarnOs get _swarn => AppScope.read(context).swarn;

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final tag = _tag.text.trim().toUpperCase();
    if (tag.isEmpty) {
      setState(() => _error = 'Enter the tag number');
      return;
    }
    if (!_swarn.configured) {
      final ok = await _settings();
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _item = null;
    });
    try {
      final item = await _swarn.itemByTag(tag);
      if (!mounted) return;
      setState(() {
        _item = item;
        _error = item == null ? 'Tag $tag is not in Swarn-OS' : null;
      });
    } on SwarnException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Server address, shop code and login. Returns true when saved.
  Future<bool> _settings() async {
    final s = _swarn;
    final url = TextEditingController(text: s.url);
    final shop = TextEditingController(text: s.shop);
    final user = TextEditingController(text: s.user);
    final pass = TextEditingController(text: s.password);
    String? status;
    var testing = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<bool> test() async {
            setLocal(() {
              testing = true;
              status = null;
            });
            try {
              final name = await s.login(
                url: url.text,
                shop: shop.text.trim(),
                user: user.text.trim(),
                password: pass.text,
              );
              setLocal(() => status = 'Connected: $name');
              return true;
            } on SwarnException catch (e) {
              setLocal(() => status = e.message);
              return false;
            } finally {
              setLocal(() => testing = false);
            }
          }

          return AlertDialog(
            title: const Text('Swarn-OS'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'The jewellery inventory system on the shop PC. On a '
                      'phone, use the PC\'s address (e.g. 192.168.1.10:8080) '
                      '— localhost only works on the PC itself.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    TextField(
                      key: const Key('swarnUrl'),
                      controller: url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Server address',
                        hintText: 'localhost:8080',
                      ),
                    ),
                    TextField(
                      key: const Key('swarnShop'),
                      controller: shop,
                      decoration: const InputDecoration(labelText: 'Shop code'),
                    ),
                    TextField(
                      key: const Key('swarnUser'),
                      controller: user,
                      decoration: const InputDecoration(labelText: 'User'),
                    ),
                    TextField(
                      key: const Key('swarnPassword'),
                      controller: pass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (testing)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(),
                      ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          status!,
                          key: const Key('swarnStatus'),
                          style: TextStyle(
                            color: status!.startsWith('Connected')
                                ? AppColors.ok
                                : AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('swarnTest'),
                onPressed: testing ? null : test,
                child: const Text('Test'),
              ),
              FilledButton(
                key: const Key('swarnSave'),
                onPressed: testing
                    ? null
                    : () async {
                        if (shop.text.trim().isEmpty ||
                            user.text.trim().isEmpty) {
                          setLocal(
                            () => status = 'Enter the shop code and user',
                          );
                          return;
                        }
                        if (!await test()) return;
                        await s.save(
                          url: url.text,
                          shop: shop.text,
                          user: user.text,
                          password: pass.text,
                        );
                        // The test signed in with these details.
                        await s.login();
                        if (context.mounted) Navigator.pop(context, true);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    return saved ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch Price'),
        actions: [
          IconButton(
            key: const Key('swarnSettings'),
            tooltip: 'Swarn-OS connection',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await _settings();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                _swarn.configured
                    ? 'From Swarn-OS (${_swarn.url}, shop ${_swarn.shop})'
                    : 'From Swarn-OS, the jewellery inventory system',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('fetchTag'),
                controller: _tag,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _fetch(),
                decoration: InputDecoration(
                  labelText: 'Tag number',
                  hintText: 'e.g. T000024',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('fetchPriceGo'),
                onPressed: _busy ? null : _fetch,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: const Text('Fetch Price'),
              ),
              if (item != null) ...[
                const SizedBox(height: 16),
                _ItemCard(item: item),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final SwarnItem item;

  @override
  Widget build(BuildContext context) {
    String g(double? v) => v == null ? '–' : '${v.toStringAsFixed(3)} g';
    String inr(double? v) => v == null ? '–' : formatInr(v);
    final rows = <(IconData, String, String)>[
      if (item.metal.isNotEmpty)
        (
          Icons.diamond_outlined,
          'Metal',
          [item.metal, item.purity].where((s) => s.isNotEmpty).join(' '),
        ),
      if ((item.grossWt ?? 0) > 0)
        (Icons.scale_outlined, 'Gross weight', g(item.grossWt)),
      if ((item.stoneWt ?? 0) > 0)
        (Icons.scale_outlined, 'Stone weight', g(item.stoneWt)),
      if ((item.netWt ?? 0) > 0)
        (Icons.scale_outlined, 'Net weight', g(item.netWt)),
      if ((item.stoneCarat ?? 0) > 0)
        (
          Icons.auto_awesome_outlined,
          'Diamonds / stones',
          '${item.stoneCarat!.toStringAsFixed(2)} ct',
        ),
      if (item.rate != null && item.rate! > 0)
        (Icons.trending_up, 'Rate', '${formatInr(item.rate!)}/g'),
      if (item.metalValue != null)
        (Icons.circle_outlined, 'Metal value', inr(item.metalValue)),
      if ((item.wastageValue ?? 0) > 0)
        (Icons.circle_outlined, 'Wastage', inr(item.wastageValue)),
      if (item.makingValue != null)
        (Icons.handyman_outlined, 'Making', inr(item.makingValue)),
      if ((item.stoneValue ?? 0) > 0)
        (
          Icons.auto_awesome_outlined,
          'Diamonds / stones value',
          inr(item.stoneValue),
        ),
      if ((item.discount ?? 0) > 0)
        (Icons.local_offer_outlined, 'Discount', '− ${inr(item.discount)}'),
      if (item.gst != null)
        (
          Icons.receipt_outlined,
          'GST${item.gstPct == null ? '' : ' ${formatPercent(item.gstPct!)}%'}',
          inr(item.gst),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              key: const Key('fetchedName'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              [
                item.tag,
                if (item.category.isNotEmpty && item.category != item.name)
                  item.category,
                if (item.huid.isNotEmpty) 'HUID ${item.huid}',
              ].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
            if (!item.inStock)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Not in stock (${item.status.replaceAll('_', ' ').toLowerCase()})',
                  key: const Key('fetchedNotInStock'),
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Divider(height: 22),
            for (final (icon, label, value) in rows)
              InfoRow(
                icon: Icon(icon, size: 18, color: AppColors.goldDeep),
                label: label,
                value: value,
              ),
            const Divider(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Price (today\'s rate)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  inr(item.price),
                  key: const Key('fetchedPrice'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldDeep,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
