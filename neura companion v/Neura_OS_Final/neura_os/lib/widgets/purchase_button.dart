import 'package:flutter/material.dart';
import '../screens/subscription_screen.dart';

class PurchaseButton extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) {
    return IconButton(
      icon: Icon(Icons.attach_money),
      onPressed: () {
        Navigator.push(ctx, MaterialPageRoute(builder: (_) => SubscriptionScreen()));
      },
    );
  }
}
