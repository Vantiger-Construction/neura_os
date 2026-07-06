import 'package:flutter/material.dart';
import '../core/neura_env.dart';
import '../screens/subscription_screen.dart';

class PurchaseButton extends StatelessWidget {
  const PurchaseButton({super.key});

  @override
  Widget build(BuildContext ctx) {
    if (!kIapEnabled) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.attach_money),
      onPressed: () {
        Navigator.push(
            ctx, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
      },
    );
  }
}
