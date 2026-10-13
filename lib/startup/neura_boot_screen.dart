import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../modules/navigation/enhanced_navigation.dart';
import '../reliability/safe_boot.dart';
import '../screens/sign_in_screen.dart';
import '../services/app_lock_prefs.dart';
import '../services/auth_service.dart';
import '../widgets/auth_guard.dart';
import 'neura_startup_avatar.dart';
import 'neura_startup_coordinator.dart';

/// Animated splash screen shown while [NeuraStartupCoordinator] runs.
///
/// Kicks off [NeuraStartupCoordinator.boot] after the first painted frame,
/// then replaces itself with [EnhancedNavigation] once [ready] fires —
/// or [SignInScreen] first, if Supabase is configured and no one is
/// signed in yet.
///
/// The screen is intentionally lightweight — no heavy widgets, no async
/// awaits of its own — so it appears on screen within a single frame of
/// [runApp].
class NeuraBootScreen extends StatefulWidget {
  const NeuraBootScreen({super.key});

  @override
  State<NeuraBootScreen> createState() => _NeuraBootScreenState();
}

class _NeuraBootScreenState extends State<NeuraBootScreen> {
  final _coordinator = NeuraStartupCoordinator.instance;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();

    // Listen for ready so we can navigate as soon as boot finishes.
    _coordinator.ready.addListener(_onReady);

    // Paint Neura before preference/native initialization begins. A returning
    // boot screen must also handle an already-ready coordinator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_coordinator.boot());
      _onReady();
    });
  }

  @override
  void dispose() {
    _coordinator.ready.removeListener(_onReady);
    super.dispose();
  }

  void _onReady() {
    if (!_coordinator.ready.value || !mounted || _navigationScheduled) return;
    _navigationScheduled = true;
    // Navigate on the next frame, without an artificial splash-screen delay.
    // Evaluate the safety/auth/lock gates at that point, rather than carrying
    // a stale decision across a delayed callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_coordinator.ready.value) return;
      // Only ask for sign-in once Supabase is actually configured — with
      // placeholder keys, Supabase.initialize() was skipped, so touching
      // Supabase.instance (AuthService included) would throw.
      final safeMode = SafeBoot.instance.safeMode.value;
      final canInspectSession = shouldInspectSupabaseSession(
        safeMode: safeMode,
        configured: SupabaseConfig.isConfigured,
        initialized: _coordinator.supabaseInitialized,
      );
      final needsSignIn = canInspectSession && AuthService.currentUser == null;
      // Device-lock only applies to the local-only dashboard path — once
      // Supabase sign-in is active it already gates identity on its own.
      final needsDeviceLock = !safeMode &&
          !needsSignIn &&
          AppLockPrefsController.instance.enabled.value;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) {
            if (needsSignIn) return const SignInScreen();
            const dashboard = EnhancedNavigation();
            return needsDeviceLock
                ? const AuthGuard(child: dashboard)
                : dashboard;
          },
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
              child: child,
            );
          },
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        ),
      );
    });
    // addPostFrameCallback alone does not request a frame when a cached-ready
    // coordinator returns to a quiet, non-animating boot screen.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Center(
          child: ValueListenableBuilder<NeuraBootStage>(
            valueListenable: _coordinator.stage,
            builder: (context, stage, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  ValueListenableBuilder<bool>(
                    valueListenable: SafeBoot.instance.safeMode,
                    builder: (context, safeMode, _) =>
                        ValueListenableBuilder<bool>(
                      valueListenable: _coordinator.booting,
                      builder: (_, booting, __) => NeuraStartupAvatar(
                        animate: booting && !safeMode,
                        height: 180,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ── App name ─────────────────────────────────────────────
                  const Text(
                    'Neura OS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<bool>(
                    valueListenable: SafeBoot.instance.safeMode,
                    builder: (context, safeMode, _) {
                      if (!safeMode) return const SizedBox.shrink();
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Chip(
                          avatar: Icon(Icons.health_and_safety, size: 18),
                          label: Text('Safe Mode'),
                        ),
                      );
                    },
                  ),
                  Text(
                    'Your AI companion',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(flex: 2),
                  ValueListenableBuilder<NeuraBootFailure?>(
                    valueListenable: _coordinator.failure,
                    builder: (context, failure, _) {
                      if (failure != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.orangeAccent,
                                size: 28,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                failure.message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () => unawaited(_coordinator.boot()),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry startup'),
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: stage.progress,
                                minHeight: 4,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.deepPurple.shade300,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              child: Text(
                                stage.label,
                                key: ValueKey(stage.label),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
