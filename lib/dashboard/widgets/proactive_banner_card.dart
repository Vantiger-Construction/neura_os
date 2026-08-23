import 'dart:async';

import 'package:flutter/material.dart';

import '../../adaptive_intent/neura_adaptive_intent_status_card.dart';
import '../../intelligence/action_review_screen.dart';
import '../../intelligence/neura_intelligence_controller.dart';
import '../../joy_engine/joy_screen.dart';
import '../../modules/quests/quest_mode_screen.dart';
import '../../modules/support/support_center_screen.dart';
import '../../relationships/screens/relationship_detail_screen.dart';
import '../../relationships/screens/relationship_list_screen.dart';
import '../../src/modules/focus/focus_office_screen.dart';
import '../proactive_banner_service.dart';

/// Surfaces Adaptive Intent state plus an optional, dismissible proactive card.
///
/// Adaptive Intent is always available from the dashboard. The optional
/// intelligence suggestion below it still follows suppression and cooldown
/// policy in [ProactiveBannerService].
class ProactiveBannerCard extends StatefulWidget {
  const ProactiveBannerCard({super.key});

  @override
  State<ProactiveBannerCard> createState() => _ProactiveBannerCardState();
}

class _ProactiveBannerCardState extends State<ProactiveBannerCard> {
  ProactiveBanner? _banner;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final banner = await ProactiveBannerService.instance
          .maybeGetBannerOnAppOpen();
      if (!mounted) return;
      setState(() => _banner = banner);
      if (banner != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _banner?.receipt.id != banner.receipt.id) return;
          unawaited(
            ProactiveBannerService.instance
                .recordShown(banner)
                .catchError((_) {}),
          );
        });
      }
    } catch (_) {
      // Proactive intelligence is optional and must never break the dashboard.
    }
  }

  void _dismiss() {
    final banner = _banner;
    if (banner != null) {
      unawaited(
        ProactiveBannerService.instance
            .recordOutcome(banner: banner, acted: false)
            .catchError((_) {}),
      );
    }
    setState(() => _dismissed = true);
  }

  Future<void> _act() async {
    final banner = _banner;
    if (banner == null || !mounted) return;
    setState(() => _dismissed = true);

    if (!(banner.kind == ProactiveBannerKind.quest &&
        banner.receipt.requiresApproval)) {
      _recordOutcome(banner, acted: true);
    }

    if (banner.kind == ProactiveBannerKind.joy && banner.joyMoment != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const NeuraJoyScreen(),
          settings: RouteSettings(arguments: banner.joyMoment),
        ),
      );
    } else if (banner.kind == ProactiveBannerKind.relationship) {
      final profile = banner.relationshipProfile;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => profile != null
              ? RelationshipDetailScreen(profile: profile)
              : const RelationshipListScreen(),
        ),
      );
    } else if (banner.kind == ProactiveBannerKind.quest) {
      if (banner.receipt.requiresApproval) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NeuraActionReviewScreen(
              candidate: banner.candidate,
              receipt: banner.receipt,
              onResolved: (acted) => _recordOutcome(banner, acted: acted),
            ),
          ),
        );
      } else {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const QuestModeScreen()));
      }
    } else if (banner.kind == ProactiveBannerKind.wellness) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SupportCenterScreen()));
    } else if (banner.kind == ProactiveBannerKind.focus) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FocusOfficeScreen()));
    }
  }

  void _recordOutcome(ProactiveBanner banner, {required bool acted}) {
    unawaited(
      ProactiveBannerService.instance
          .recordOutcome(banner: banner, acted: acted)
          .catchError((_) {}),
    );
  }

  Future<void> _showWhy() async {
    final banner = _banner;
    if (banner == null) return;
    final receipt = banner.receipt;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Why Neura suggested this',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Priority score ${(receipt.score * 100).round()}/100 • '
              '${receipt.risk.name} risk',
            ),
            const SizedBox(height: 8),
            Text(
              receipt.requiresApproval
                  ? 'This is a preview. Neura cannot make the change until you review and approve it.'
                  : 'Nothing happens unless you tap Open.',
            ),
            const SizedBox(height: 12),
            ...receipt.reasons.map(
              (reason) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 20),
                title: Text(reason),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${receipt.evidenceIds.length} local evidence '
              '${receipt.evidenceIds.length == 1 ? 'signal' : 'signals'} used. '
              'Raw journal and therapy text are excluded.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (banner == null || _dismissed) {
      return const NeuraAdaptiveIntentStatusCard();
    }

    final icon = switch (banner.kind) {
      ProactiveBannerKind.joy => Icons.emoji_emotions_outlined,
      ProactiveBannerKind.relationship => Icons.people_alt_outlined,
      ProactiveBannerKind.quest => Icons.flag_outlined,
      ProactiveBannerKind.wellness => Icons.self_improvement_outlined,
      ProactiveBannerKind.focus => Icons.center_focus_strong_outlined,
    };
    final showWhy =
        NeuraIntelligenceController.instance.preferences.showDecisionReasons;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NeuraAdaptiveIntentStatusCard(),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        banner.body,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: _dismiss,
                            child: const Text('Not now'),
                          ),
                          if (showWhy)
                            TextButton(
                              onPressed: _showWhy,
                              child: const Text('Why?'),
                            ),
                          FilledButton(
                            onPressed: _act,
                            child: Text(
                              banner.receipt.requiresApproval
                                  ? 'Review'
                                  : 'Open',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
