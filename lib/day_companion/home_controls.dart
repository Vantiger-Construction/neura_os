import 'package:flutter/material.dart';

import 'home_action.dart';
import 'day_companion_cues.dart';

class DayHomeControls extends StatefulWidget {
  const DayHomeControls(
      {super.key,
      required this.actions,
      required this.onAdd,
      required this.onSelect,
      required this.onRemove});
  final List<HomeAction> actions;
  final ValueChanged<HomeAction> onAdd, onSelect, onRemove;

  @override
  State<DayHomeControls> createState() => _DayHomeControlsState();
}

class _DayHomeControlsState extends State<DayHomeControls> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;
  PenthouseCue? _cue;

  void _add() {
    try {
      final action = HomeAction.configure(_name.text, _url.text, cue: _cue);
      if (widget.actions.any((a) =>
          a.label.toLowerCase() == action.label.toLowerCase() ||
          a.endpoint == action.endpoint)) {
        throw const FormatException(
            'Each action needs its own name and webhook.');
      }
      if (_cue != null && widget.actions.any((a) => a.cue == _cue)) {
        throw const FormatException('That cue already has a linked action.');
      }
      widget.onAdd(action);
      _cue = null;
      _name.clear();
      _url.clear();
      setState(() => _error = null);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('Real devices · Home Assistant'),
        children: [
          const Text(
              'In Home Assistant, create a local-only PUT webhook for one action. Name the device and exact change, such as “Turn on the desk Hue light”. Say “Neura” and that name to bring it up for approval.'),
          for (final action in widget.actions)
            ListTile(
                title: Text(action.label),
                onTap: () => widget.onSelect(action),
                trailing: IconButton(
                    tooltip: 'Remove action',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => widget.onRemove(action))),
          if (widget.actions.length < 8) ...[
            TextField(
                controller: _name,
                maxLength: 72,
                decoration:
                    const InputDecoration(labelText: 'Device and action')),
            TextField(
                controller: _url,
                obscureText: true,
                maxLength: 400,
                enableIMEPersonalizedLearning: false,
                enableSuggestions: false,
                autocorrect: false,
                decoration:
                    const InputDecoration(labelText: 'Local webhook URL')),
            const Text(
                'Use HTTPS when available. HTTP exposes the secret link to your local network. Links are cleared when you leave.'),
            const Text('When should Neura suggest this action?'),
            Wrap(spacing: 8, children: [
              for (final option in const {
                null: 'By name only',
                PenthouseCue.focus: 'Also for focus',
                PenthouseCue.windDown: 'Also for winding down',
              }.entries)
                ChoiceChip(
                    label: Text(option.value),
                    selected: _cue == option.key,
                    onSelected: (_) => setState(() => _cue = option.key)),
            ]),
            if (_error != null) Text(_error!),
            TextButton(
                onPressed: _add,
                child: const Text('Add action for this session')),
          ],
        ],
      );
}
