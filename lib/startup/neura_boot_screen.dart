import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../modules/navigation/enhanced_navigation.dart';
import '../screens/sign_in_screen.dart';
import '../services/app_lock_prefs.dart';
import '../services/auth_service.dart';
import '../widgets/auth_guard.dart';
import 'neura_startup_coordinator.dart';

/// Animated splash screen shown while [NeuraStartupCoordinator] runs.
///
/// Immediately kicks off [NeuraStartupCoordinator.boot] on first build,
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

class _NeuraBootScreenState extends State<NeuraBootScreen>
    with SingleTickerProviderStateMixin {
  final _coordinator = NeuraStartupCoordinator.instance;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    // Gentle pulsing glow on the logo while booting.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for ready so we can navigate as soon as boot finishes.
    _coordinator.ready.addListener(_onReady);

    // Fire the boot sequence (idempotent — safe to call here).
    _coordinator.boot();
  }

  @override
  void dispose() {
    _coordinator.ready.removeListener(_onReady);
    _pulseController.dispose();
    super.dispose();
  }

  void _onReady() {
    if (!_coordinator.ready.value) return;
    if (!mounted) return;
    // Only ask for sign-in once Supabase is actually configured — with
    // placeholder keys, Supabase.initialize() was skipped, so touching
    // Supabase.instance (AuthService included) would throw.
    final needsSignIn =
        SupabaseConfig.isConfigured && AuthService.currentUser == null;
    // Device-lock only applies to the local-only dashboard path — once
    // Supabase sign-in is active it already gates identity on its own.
    final needsDeviceLock =
        !needsSignIn && AppLockPrefsController.instance.enabled.value;
    // Short pause so "Ready!" is readable, then replace the whole route stack.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
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
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeIn,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
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
                  // ── Logo / avatar placeholder ────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) {
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.deepPurple.shade900,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.deepPurple.withValues(
                                alpha: _pulseAnim.value * 0.7,
                              ),
                              blurRadius: 40,
                              spreadRadius: 12,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'N',
                            style: TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(
                                alpha: _pulseAnim.value,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
                  Text(
                    'Your AI companion',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // ── Progress bar ─────────────────────────────────────────
                  Padding(
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
                          duration: const Duration(milliseconds: 200),
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
