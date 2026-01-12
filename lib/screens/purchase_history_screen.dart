import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/billing_service.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  @override
  _PurchaseHistoryScreenState createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  final BillingService _billing = BillingService();
  bool _loading = true;
  List<PurchaseDetails> _purchases = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await _billing.init();
    // TODO: load past purchases into _purchases
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext ctx) {
    if (_loading)
      return Scaffold(
          appBar: AppBar(title: Text('Purchase History')),
          body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text('Purchase History')),
      body: ListView(
        children: _purchases
            .map((p) => ListTile(
                  title: Text(p.productID),
                  subtitle: Text(p.status.toString()),
                ))
            .toList(),
      ),
    );
  }
}


