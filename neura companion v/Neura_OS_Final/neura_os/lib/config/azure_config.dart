/// Optional Azure configuration.
///
/// This is intentionally dependency-free. If you later re-enable Azure
/// integration, wire this into your preferred DI/Provider system.
class AzureConfig {
  final String accountName;
  final String accountKey;

  const AzureConfig({required this.accountName, required this.accountKey});

  bool get isConfigured => accountName.isNotEmpty && accountKey.isNotEmpty;
}

const AzureConfig defaultAzureConfig = AzureConfig(accountName: '', accountKey: '');
