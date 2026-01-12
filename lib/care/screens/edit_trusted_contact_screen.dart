import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/trusted_contact.dart';
import '../services/trusted_contacts_service.dart';

class EditTrustedContactScreen extends StatefulWidget {
  final TrustedContact? existing;

  const EditTrustedContactScreen({Key? key, this.existing}) : super(key: key);

  @override
  State<EditTrustedContactScreen> createState() =>
      _EditTrustedContactScreenState();
}

class _EditTrustedContactScreenState extends State<EditTrustedContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isEmergency = false;
  bool _isProfessional = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _relationshipController.text = existing.relationship;
      _phoneController.text = existing.phoneNumber;
      _notesController.text = existing.notes;
      _isEmergency = existing.isEmergency;
      _isProfessional = existing.isProfessional;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final service = TrustedContactsService.instance;
    final existing = widget.existing;
    final id = existing?.id ?? const Uuid().v4();

    final contact = TrustedContact(
      id: id,
      name: _nameController.text.trim(),
      relationship: _relationshipController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      isEmergency: _isEmergency,
      isProfessional: _isProfessional,
      notes: _notesController.text.trim(),
    );

    await service.addOrUpdate(contact);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Trusted Contact' : 'Add Trusted Contact'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Please enter a name.'
                        : null,
              ),
              TextFormField(
                controller: _relationshipController,
                decoration: const InputDecoration(labelText: 'Relationship'),
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Emergency contact'),
                subtitle: const Text(
                    'Show near the top when you are not feeling safe.'),
                value: _isEmergency,
                onChanged: (v) {
                  setState(() {
                    _isEmergency = v;
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Professional (therapist, doctor, etc.)'),
                value: _isProfessional,
                onChanged: (v) {
                  setState(() {
                    _isProfessional = v;
                  });
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _save,
                child: Text(isEditing ? 'Save changes' : 'Add contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
