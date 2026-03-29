import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionCard extends StatelessWidget {
  final ProductDetails product;
  final VoidCallback onBuy;

  const SubscriptionCard(
      {super.key, required this.product, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        title: Text(product.title),
        subtitle: Text(product.description),
        trailing: ElevatedButton(
          onPressed: onBuy,
          child: Text(product.price),
        ),
      ),
    );
  }
}
