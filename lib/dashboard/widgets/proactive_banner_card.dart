import 'dart:async';

import 'package:flutter/material.dart';

import '../../joy_engine/joy_screen.dart';
import '../../relationships/screens/relationship_detail_screen.dart';
import '../../relationships/screens/relationship_list_screen.dart';
import '../proactive_banner_service.dart';

/// Surfaces an unprompted, dismissible Joy Moment or relationship nudge at
/// the top of the dashboard -- see [ProactiveBannerService] for the
/// suppression/cooldown logic behind when this actually shows anything.
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
    final banner = await ProactiveBannerService.instance.maybeGetBannerOnAppOpen();
    if (!mounted) return;
    setState(() => _banner = banner);
  }

  void _dismiss() {
    unawaited(ProactiveBannerService.instance.recordOutcome(acted: false));
    setState(() => _dismissed = true);
  }

  Future<void> _act() async {
    unawaited(ProactiveBannerService.instance.recordOutcome(acted: true));
    final banner = _banner;
    if (banner == null || !mounted) return;
    setState(() => _dismissed = true);

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (banner == null || _dismissed) return const SizedBox.shrink();

    final icon = banner.kind == ProactiveBannerKind.joy
        ? Icons.emoji_emotions_outlined
        : Icons.people_alt_outlined;

    return Card(
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
                  Text(banner.title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(banner.body, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(onPressed: _dismiss, child: const Text('Not now')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _act, child: const Text('Open')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
