import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _user = FirebaseAuth.instance.currentUser!;
  final _picker = ImagePicker();
  String? _displayName;
  File? _avatar;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _displayName = _user.displayName;
  }

  Future<void> _pickAvatar() async {
    final img = await _picker.pickImage(source: ImageSource.gallery);
    if (img != null) setState(() => _avatar = File(img.path));
  }

  Future<void> _save() async {
    setState(() => _updating = true);
    if (_avatar != null) {
      final ref = FirebaseStorage.instance.ref('avatars/${_user.uid}.jpg');
      await ref.putFile(_avatar!);
      final url = await ref.getDownloadURL();
      await _user.updatePhotoURL(url);
    }
    await _user.updateDisplayName(_displayName);
    await _user.reload();
    setState(() => _updating = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Profile updated')));
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: [
        IconButton(
            icon: Icon(Icons.logout), onPressed: () => AuthService().signOut())
      ]),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 40,
                backgroundImage: _avatar != null
                    ? FileImage(_avatar!)
                    : (_user.photoURL != null
                        ? NetworkImage(_user.photoURL!)
                        : null) as ImageProvider?,
                child: _avatar == null && _user.photoURL == null
                    ? Icon(Icons.person, size: 40)
                    : null,
              ),
            ),
            TextField(
              decoration: InputDecoration(labelText: 'Display Name'),
              onChanged: (v) => _displayName = v,
              controller: TextEditingController(text: _displayName),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _updating ? null : _save,
              child: _updating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Save Profile'),
            ),
          ],
        ),
      ),
    );
  }
}
