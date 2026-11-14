import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';

/// Admission and revocation for temporary, explicitly opened support drafts.
abstract class PrivateSupportState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  int requestGeneration = 0;
  int editorGeneration = 0;
  bool _foreground = true;
  bool _visible = true;

  bool get mayUse =>
      mounted &&
      _foreground &&
      _visible &&
      !SafeBoot.instance.restartRequired.value;
  bool get mayReadSaved => mayUse && !SafeBoot.instance.safeMode.value;
  bool isCurrent(int request) => mayUse && request == requestGeneration;

  void clearPrivateContent();

  void invalidateDraft() {
    requestGeneration++;
    editorGeneration++;
    clearPrivateContent();
  }

  void _safetyChanged() {
    if (mounted) setState(invalidateDraft);
  }

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible && !visible) invalidateDraft();
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) invalidateDraft();
    });
  }

  @override
  void dispose() {
    requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    super.dispose();
  }
}
