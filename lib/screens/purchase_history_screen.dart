import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../core/neura_env.dart';
import '../services/billing_service.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  final BillingService _billing = BillingService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _billing.init();
    _billing.purchases.addListener(_onPurchasesChanged);
    if (mounted) setState(() => _loading = false);
  }

  void _onPurchasesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _billing.purchases.removeListener(_onPurchasesChanged);
    _billing.dispose();
    super.dispose();
  }

  IconData _iconFor(PurchaseStatus status) {
    switch (status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        return Icons.check_circle_outline;
      case PurchaseStatus.pending:
        return Icons.hourglass_empty_outlined;
      case PurchaseStatus.error:
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  Color _colorFor(PurchaseStatus status, ColorScheme cs) {
    switch (status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        return cs.primary;
      case PurchaseStatus.pending:
        return cs.secondary;
      case PurchaseStatus.error:
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIapEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase History')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Purchase history is not available in this beta.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final purchases = _billing.purchases.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase History'),
        actions: [
          IconButton(
            tooltip: 'Restore purchases',
            icon: const Icon(Icons.restore),
            onPressed: _loading
                ? null
                : () async {
                    setState(() => _loading = true);
                    await _billing.restorePurchases();
                    if (mounted) setState(() => _loading = false);
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : purchases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 56, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No purchases found.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: purchases.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = purchases[i];
                    final status = p.status;
                    return ListTile(
                      leading: Icon(_iconFor(status),
                          color: _colorFor(status, cs)),
                      title: Text(p.productID),
                      subtitle: Text(
                        status.toString().replaceFirst('PurchaseStatus.', ''),
                        style: TextStyle(
                            color: _colorFor(status, cs), fontSize: 12),
                      ),
                      trailing: p.transactionDate != null
                          ? Text(
                              _formatDate(p.transactionDate!),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            )
                          : null,
                    );
                  },
                ),
    );
  }

  String _formatDate(String isoOrMs) {
    try {
      final ms = int.tryParse(isoOrMs);
      final dt = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.parse(isoOrMs);
      final y = dt.year;
      final mo = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$mo-$d';
    } catch (_) {
      return isoOrMs;
    }
  }
}
