class AzureConfig {
  final String accountName;
  final String accountKey;

  AzureConfig({required this.accountName, required this.accountKey});
}

/// Default placeholder config for local/dev usage.
///
/// Replace with secure loading (env vars, secure storage, etc.) before shipping.
final AzureConfig defaultAzureConfig = AzureConfig(
  accountName: 'your_account_name',
  accountKey: 'your_account_key',
);
