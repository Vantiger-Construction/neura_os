import 'dart:convert';

class TrustedContact {
  final String id;
  final String name;
  final String relationship;
  final String phoneNumber;
  final bool isEmergency;
  final bool isProfessional;
  final String notes;

  TrustedContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    required this.isEmergency,
    required this.isProfessional,
    required this.notes,
  });

  TrustedContact copyWith({
    String? id,
    String? name,
    String? relationship,
    String? phoneNumber,
    bool? isEmergency,
    bool? isProfessional,
    String? notes,
  }) {
    return TrustedContact(
      id: id ?? this.id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isEmergency: isEmergency ?? this.isEmergency,
      isProfessional: isProfessional ?? this.isProfessional,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'phoneNumber': phoneNumber,
      'isEmergency': isEmergency,
      'isProfessional': isProfessional,
      'notes': notes,
    };
  }

  factory TrustedContact.fromMap(Map<String, dynamic> map) {
    return TrustedContact(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      isEmergency: map['isEmergency'] as bool? ?? false,
      isProfessional: map['isProfessional'] as bool? ?? false,
      notes: map['notes'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory TrustedContact.fromJson(String source) =>
      TrustedContact.fromMap(json.decode(source) as Map<String, dynamic>);
}
