import 'package:flutter/material.dart';

import 'portal_route.dart';
import 'rooms_catalog.dart';
import 'shell_prefs.dart';

class RoomsMapScreen extends StatefulWidget {
  const RoomsMapScreen({super.key});

  @override
  State<RoomsMapScreen> createState() => _RoomsMapScreenState();
}

class _RoomsMapScreenState extends State<RoomsMapScreen> {
  final TextEditingController _search = TextEditingController();
  RoomCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = RoomsCatalog.all();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Rooms'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _category = null;
                _search.clear();
              });
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search rooms…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(context, null, 'All'),
                  _chip(context, RoomCategory.core, 'Core'),
                  _chip(context, RoomCategory.mood, 'Mood'),
                  _chip(context, RoomCategory.journal, 'Journal'),
                  _chip(context, RoomCategory.dreams, 'Dreams'),
                  _chip(context, RoomCategory.legacy, 'Legacy'),
                  _chip(context, RoomCategory.tools, 'Tools'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: ShellPrefsController.instance.prefs,
                builder: (context, prefs, _) {
                  final filtered = rooms.where((r) {
                    final q = _search.text.trim().toLowerCase();
                    final matchesQ = q.isEmpty || r.title.toLowerCase().contains(q) || r.subtitle.toLowerCase().contains(q);
                    final matchesCat = _category == null || r.category == _category;
                    return matchesQ && matchesCat;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No rooms match that search.\n(Neura checked. Twice.)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final room = filtered[i];
                      return _RoomCard(
                        room: room,
                        walkingShimmer: prefs.walkingShimmer,
                        onOpen: () => _openRoom(context, room, prefs.portalFx),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, RoomCategory? cat, String label) {
    final selected = _category == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _category = cat),
      ),
    );
  }

  Future<void> _openRoom(BuildContext context, RoomItem room, bool portalFx) async {
    await PortalNav.push(context, Builder(builder: room.builder), enabled: portalFx);
  }
}

class _RoomCard extends StatefulWidget {
  final RoomItem room;
  final bool walkingShimmer;
  final VoidCallback onOpen;

  const _RoomCard({required this.room, required this.walkingShimmer, required this.onOpen});

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: Stack(
          children: [
            if (widget.walkingShimmer) Positioned.fill(child: _ShimmerLine(animation: _c)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: Icon(room.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(room.title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(room.subtitle, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final Animation<double> animation;
  const _ShimmerLine({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return CustomPaint(
          painter: _LinePainter(t),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  final double t;
  _LinePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 8;
    final dx = (size.width + 120) * t - 120;
    final rect = Rect.fromLTWH(0, y - 2, size.width, 4);

    canvas.clipRect(rect);

    final p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.cyanAccent.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(dx, y - 2, 120, 4));

    canvas.drawRect(Rect.fromLTWH(dx, y - 2, 120, 4), p);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => oldDelegate.t != t;
}
