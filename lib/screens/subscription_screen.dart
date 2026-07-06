import 'package:flutter/material.dart';
import '../core/neura_env.dart';
import '../services/billing_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final BillingService _billing = BillingService();
  List<ProductDetails> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (kIapEnabled) _initBilling();
  }

  Future<void> _initBilling() async {
    await _billing.init();
    final products =
        await _billing.fetchProducts(['monthly_sub', 'yearly_sub', 'lifetime']);
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  void _buy(ProductDetails product) {
    _billing.purchase(product);
  }

  @override
  Widget build(BuildContext ctx) {
    if (!kIapEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscriptions')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Subscriptions are not available in this beta.\nThey will be enabled in the public release.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Subscriptions')),
          body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      body: ListView(
        children: _products
            .map((p) => ListTile(
                  title: Text(p.title),
                  subtitle: Text(p.price),
                  trailing: ElevatedButton(
                    onPressed: () => _buy(p),
                    child: const Text('Buy'),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
