import 'package:flutter_riverpod/flutter_riverpod.dart';

class AzureConfig {
  final String accountName;
  final String accountKey;

  AzureConfig({required this.accountName, required this.accountKey});
}

final azureConfigProvider = Provider<AzureConfig>((ref) {
  return AzureConfig(
    accountName: 'your_account_name',
    accountKey: 'your_account_key',
  );
});
