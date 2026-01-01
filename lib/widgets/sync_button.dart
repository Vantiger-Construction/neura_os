import 'package:flutter/material.dart';
import '../screens/sync_status_screen.dart';

class SyncButton extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) {
    return IconButton(
      icon: Icon(Icons.sync),
      onPressed: () {
        Navigator.push(ctx, MaterialPageRoute(builder: (_) => SyncStatusScreen()));
      },
    );
  }
}
