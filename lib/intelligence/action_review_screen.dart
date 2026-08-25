import 'package:flutter/material.dart';

import '../modules/quests/quest_mode_screen.dart';
import 'action_loom.dart';
import 'approval_broker.dart';
import 'models.dart';

class NeuraActionReviewScreen extends StatefulWidget {
  const NeuraActionReviewScreen({
    required this.candidate,
    required this.receipt,
    this.onResolved,
    super.key,
  });

  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final ValueChanged<bool>? onResolved;

  @override
  State<NeuraActionReviewScreen> createState() =>
      _NeuraActionReviewScreenState();
}

class _NeuraActionReviewScreenState extends State<NeuraActionReviewScreen> {
  NeuraApprovalAction? _action;
  bool _busy = true;
  bool _resolved = false;
  String? _error;

  void _resolve(bool acted) {
    if (_resolved) return;
    _resolved = true;
    widget.onResolved?.call(acted);
  }

  @override
  void initState() {
    super.initState();
    _submit();
  }

  Future<void> _submit() async {
    try {
      final action =
          await NeuraActionLoom.instance.submit(_actionScopedDecision());
      if (!mounted) return;
      setState(() {
        _action = action;
        _busy = false;
      });
      if (action.status == NeuraApprovalStatus.executed) {
        _resolve(true);
      } else if (action.status == NeuraApprovalStatus.denied) {
        _resolve(false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'This action could not be prepared (${error.runtimeType}).';
        _busy = false;
      });
    }
  }

  /// Radar ids remain stable for suggestion deduplication, while an approval
  /// submission is bound to one exact council receipt. A later re-evaluation
  /// therefore gets a fresh action id without weakening payload binding.
  NeuraCouncilDecision _actionScopedDecision() {
    final candidate = widget.candidate;
    final receipt = widget.receipt;
    final actionCandidateId = '${candidate.id}:decision:'
        '${receipt.evaluatedAt.toUtc().microsecondsSinceEpoch}';
    return NeuraCouncilDecision(
      candidate: NeuraIntelligenceCandidate(
        id: actionCandidateId,
        capabilityId: candidate.capabilityId,
        specialistId: candidate.specialistId,
        title: candidate.title,
        body: candidate.body,
        createdAt: candidate.createdAt,
        expiresAt: candidate.expiresAt,
        evidence: candidate.evidence,
        benefit: candidate.benefit,
        urgency: candidate.urgency,
        disruption: candidate.disruption,
        confidence: candidate.confidence,
        payload: candidate.payload,
      ),
      receipt: NeuraDecisionReceipt(
        id: receipt.id,
        candidateId: actionCandidateId,
        capabilityId: receipt.capabilityId,
        specialistId: receipt.specialistId,
        outcome: receipt.outcome,
        risk: receipt.risk,
        score: receipt.score,
        requiresApproval: receipt.requiresApproval,
        reasons: receipt.reasons,
        evidenceIds: receipt.evidenceIds,
        evaluatedAt: receipt.evaluatedAt,
        userOutcome: receipt.userOutcome,
      ),
    );
  }

  Future<void> _approve() async {
    final current = _action;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      final approved = await NeuraActionLoom.instance.approve(current.id);
      if (approved.status != NeuraApprovalStatus.approved) {
        if (!mounted) return;
        setState(() {
          _action = approved;
          _busy = false;
          _error = approved.policyReason ??
              approved.failure ??
              'The action is ${approved.status.name}.';
        });
        return;
      }
      final executed = await NeuraActionLoom.instance.execute(approved.id);
      if (!mounted) return;
      setState(() {
        _action = executed;
        _busy = false;
        _error = executed.status == NeuraApprovalStatus.executed
            ? null
            : executed.policyReason ?? executed.failure;
      });
      if (executed.status == NeuraApprovalStatus.executed) {
        _resolve(true);
      }
    } catch (error) {
      if (!mounted) return;
      final latest = NeuraActionLoom.instance.broker.find(current.id);
      setState(() {
        if (latest != null) _action = latest;
        _error = 'The action was not applied (${error.runtimeType}).';
        _busy = false;
      });
      if (latest?.status == NeuraApprovalStatus.executed) _resolve(true);
    }
  }

  Future<void> _deny() async {
    final current = _action;
    if (current != null &&
        (current.status == NeuraApprovalStatus.pendingApproval ||
            current.status == NeuraApprovalStatus.approved ||
            current.status == NeuraApprovalStatus.policyHeld)) {
      setState(() => _busy = true);
      try {
        final denied = await NeuraActionLoom.instance.deny(current.id);
        if (denied.status == NeuraApprovalStatus.denied) _resolve(false);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'The action could not be cancelled (${error.runtimeType}).';
        });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry() async {
    final current = _action;
    if (current == null ||
        (current.status != NeuraApprovalStatus.policyHeld &&
            current.status != NeuraApprovalStatus.approved) ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final retried = await NeuraActionLoom.instance.execute(current.id);
      if (!mounted) return;
      setState(() {
        _action = retried;
        _busy = false;
        _error = retried.status == NeuraApprovalStatus.executed
            ? null
            : retried.policyReason ?? retried.failure;
      });
      if (retried.status == NeuraApprovalStatus.executed) _resolve(true);
    } catch (error) {
      if (!mounted) return;
      final latest = NeuraActionLoom.instance.broker.find(current.id);
      setState(() {
        if (latest != null) _action = latest;
        _busy = false;
        _error = 'The action is not complete (${error.runtimeType}).';
      });
      if (latest?.status == NeuraApprovalStatus.executed) _resolve(true);
    }
  }

  Future<void> _undo() async {
    final current = _action;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      final undone = await NeuraActionLoom.instance.undo(current.id);
      if (!mounted) return;
      setState(() {
        _action = undone;
        _busy = false;
        _error = undone.status == NeuraApprovalStatus.undone
            ? null
            : undone.policyReason ?? undone.failure;
      });
    } catch (error) {
      if (!mounted) return;
      final latest = NeuraActionLoom.instance.broker.find(current.id);
      setState(() {
        if (latest != null) _action = latest;
        _busy = false;
        _error = 'The undo could not be completed (${error.runtimeType}).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _action;
    final status = action?.status;
    final executed = status == NeuraApprovalStatus.executed;
    final undone = status == NeuraApprovalStatus.undone;
    final approved = status == NeuraApprovalStatus.approved;
    final policyHeld = status == NeuraApprovalStatus.policyHeld;
    final canApprove = status == NeuraApprovalStatus.pendingApproval;
    final candidate = action?.candidate ?? widget.candidate;
    final receipt = action?.receipt ?? widget.receipt;
    final goal = candidate.payload['goal']?.toString();
    final statusReason = action?.policyReason ?? action?.failure;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Neura action')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fact_check_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          candidate.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(candidate.body),
                  if (goal != null && goal.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Proposed quest: Take one step toward "$goal"',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('Details: Make it tiny — 5–15 minutes.'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consent receipt',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${receipt.risk.name} risk • '
                    '${(receipt.score * 100).round()}/100 priority score',
                  ),
                  const SizedBox(height: 8),
                  Text(_consentCopy(status)),
                  const SizedBox(height: 8),
                  ...receipt.reasons.map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $reason'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (executed) ...[
            const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Quest created'),
              subtitle: Text('The approved local change is now active.'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QuestModeScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Open Quest Mode'),
                ),
              ],
            ),
          ] else if (undone)
            const ListTile(
              leading: Icon(Icons.undo),
              title: Text('Quest creation undone'),
              subtitle: Text('No further action is pending.'),
            )
          else if (policyHeld)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _deny,
                  child: const Text('Cancel action'),
                ),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry policy check'),
                ),
              ],
            )
          else if (approved)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _deny,
                  child: const Text('Cancel action'),
                ),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Apply approved action'),
                ),
              ],
            )
          else if (canApprove)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _deny,
                  child: const Text('Not now'),
                ),
                FilledButton.icon(
                  onPressed: _approve,
                  icon: const Icon(Icons.check),
                  label: const Text('Approve once'),
                ),
              ],
            )
          else
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text('Action status: ${status?.name ?? 'unavailable'}'),
              subtitle: statusReason == null ? null : Text(statusReason),
            ),
        ],
      ),
    );
  }

  String _consentCopy(NeuraApprovalStatus? status) {
    return switch (status) {
      NeuraApprovalStatus.approved =>
        'Approval is recorded, but the local change has not completed yet.',
      NeuraApprovalStatus.policyHeld =>
        'Approval is recorded. A current safety policy is holding the write. '
            'Retry after the condition changes, or cancel it.',
      NeuraApprovalStatus.executed =>
        'The approved local quest was created. Undo remains available here '
            'only while no progress has been recorded for it.',
      NeuraApprovalStatus.undone =>
        'The quest creation was undone. No further action is pending.',
      NeuraApprovalStatus.denied =>
        'You declined this proposal. No local change was made.',
      NeuraApprovalStatus.expired =>
        'This proposal expired before it could be applied.',
      NeuraApprovalStatus.blocked =>
        'Current autonomy policy blocked this proposal. No change was made.',
      NeuraApprovalStatus.failed =>
        'The action did not complete. Review the status below before retrying '
            'from a new proposal.',
      _ => 'Nothing has changed yet. Approve once to create this quest. '
          'Neura will re-check policy immediately before writing.',
    };
  }
}
