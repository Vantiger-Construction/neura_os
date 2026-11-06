enum ClinicContactChannel { phone, portal }

enum ClinicContactPurpose {
  appointment('Appointment request'),
  question('Question for my care team'),
  followUp('Follow-up request');

  const ClinicContactPurpose(this.label);
  final String label;
}

/// A temporary, person-entered brief. This never reads Neura's private stores
/// or infers medical facts. It is not a transport or a delivery receipt.
class ClinicContactDraft {
  const ClinicContactDraft({
    required this.personName,
    required this.clinicName,
    required this.purpose,
    required this.notes,
    required this.channel,
    required this.destination,
  });

  final String personName;
  final String clinicName;
  final ClinicContactPurpose purpose;
  final String notes;
  final ClinicContactChannel channel;
  final String destination;

  String get message => 'To: ${clinicName.trim()}\n'
      'From: ${personName.trim()}\n'
      'Request: ${purpose.label}\n\n'
      'Notes supplied by the person:\n${notes.trim()}\n\n'
      'Prepared with Neura, an AI assistant. '
      'Please respond through your usual patient contact process.';

  Uri? get handoffUri => switch (channel) {
        ClinicContactChannel.phone => phoneUri(destination),
        ClinicContactChannel.portal => portalUri(destination),
      };

  /// Only ordinary clinic numbers, without dial commands, extensions, USSD,
  /// query strings or pauses. The platform chooses how to handle a tel link.
  static Uri? phoneUri(String value) {
    final text = value.trim();
    if (!RegExp(r'^\+?[0-9 ()\-.]+$').hasMatch(text)) return null;
    final number = text.replaceAll(RegExp(r'[ ()\-.]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) return null;
    return Uri(scheme: 'tel', path: number);
  }

  /// Accept a clinic's HTTPS sign-in address, without credentials or data in
  /// a query/fragment. Syntax checks do not verify clinic ownership.
  static Uri? portalUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final labels = host.split('.');
    if (labels.length < 2 ||
        !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
        const {'local', 'localhost', 'internal', 'home'}
            .contains(labels.last) ||
        labels.any((label) =>
            label.isEmpty ||
            label.length > 63 ||
            !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label))) {
      return null;
    }
    return uri;
  }
}
