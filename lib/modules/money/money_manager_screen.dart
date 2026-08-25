import 'package:flutter/material.dart';

import 'add_transaction_sheet.dart';
import 'money_models.dart';
import 'money_store.dart';

class MoneyManagerScreen extends StatefulWidget {
  const MoneyManagerScreen({super.key});

  @override
  State<MoneyManagerScreen> createState() => _MoneyManagerScreenState();
}

class _MoneyManagerScreenState extends State<MoneyManagerScreen> {
  List<MoneyEntry> _entries = const [];
  double _balance = 0;
  double _monthIncome = 0;
  double _monthExpense = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await MoneyStore.instance.getAll();
    final balance = await MoneyStore.instance.balance();
    final summary = await MoneyStore.instance.thisMonthSummary();
    if (!mounted) return;
    setState(() {
      _entries = entries.reversed.toList(); // newest first
      _balance = balance;
      _monthIncome = summary.income;
      _monthExpense = summary.expense;
      _loading = false;
    });
  }

  Future<void> _addTransaction() async {
    final entry = await showModalBottomSheet<MoneyEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddTransactionSheet(),
    );
    if (entry == null) return;
    await MoneyStore.instance.add(entry);
    await _load();
  }

  Future<void> _delete(MoneyEntry entry) async {
    await MoneyStore.instance.remove(entry.id);
    await _load();
  }

  String _money(double v) => '\$${v.abs().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Money Manager')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text('Balance', style: TextStyle(fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                            '${_balance < 0 ? '-' : ''}${_money(_balance)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _balance < 0 ? Colors.redAccent : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _SummaryChip(
                                  label: 'In this month',
                                  value: _money(_monthIncome),
                                  color: Colors.green),
                              _SummaryChip(
                                  label: 'Out this month',
                                  value: _money(_monthExpense),
                                  color: Colors.redAccent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child:
                              Text('No transactions yet. Tap Add to log one.')),
                    )
                  else
                    ..._entries.map((e) => Dismissible(
                          key: ValueKey(e.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: Colors.redAccent,
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _delete(e),
                          child: ListTile(
                            leading: Icon(
                              e.type == MoneyEntryType.income
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: e.type == MoneyEntryType.income
                                  ? Colors.green
                                  : Colors.redAccent,
                            ),
                            title: Text(e.category),
                            subtitle: e.note.isEmpty ? null : Text(e.note),
                            trailing: Text(
                              '${e.type == MoneyEntryType.income ? '+' : '-'}${_money(e.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: e.type == MoneyEntryType.income
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
