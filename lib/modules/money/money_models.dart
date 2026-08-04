import 'package:flutter/foundation.dart';

enum MoneyEntryType { income, expense }

const List<String> kMoneyCategories = [
  'Food',
  'Housing',
  'Transport',
  'Bills',
  'Health',
  'Fun',
  'Shopping',
  'Savings',
  'Income',
  'Other',
];

@immutable
class MoneyEntry {
  final String id;
  final DateTime timestamp;
  final double amount; // always positive; sign comes from [type]
  final MoneyEntryType type;
  final String category;
  final String note;

  const MoneyEntry({
    required this.id,
    required this.timestamp,
    required this.amount,
    required this.type,
    required this.category,
    this.note = '',
  });

  /// Signed amount for balance math - positive for income, negative for expense.
  double get signedAmount => type == MoneyEntryType.income ? amount : -amount;

  Map<String, Object?> toJson() => {
        'id': id,
        'ts': timestamp.toUtc().toIso8601String(),
        'amount': amount,
        'type': type.name,
        'category': category,
        'note': note,
      };

  factory MoneyEntry.fromJson(Map<String, Object?> json) => MoneyEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['ts'] as String).toLocal(),
        amount: (json['amount'] as num).toDouble(),
        type: MoneyEntryType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => MoneyEntryType.expense,
        ),
        category: json['category'] as String? ?? 'Other',
        note: json['note'] as String? ?? '',
      );
}
