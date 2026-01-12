import 'package:hive/hive.dart';
import 'package:neura_companion/models/usage_entry.dart';

class HiveUsageEntryAdapter extends TypeAdapter<UsageEntry> {
  @override
  final int typeId = 0;

  @override
  UsageEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UsageEntry(
      id: fields[0] as String,
      timestamp: fields[1] as DateTime,
      type: fields[2] as String,
      source: fields[3] as String,
      moodTag: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UsageEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.moodTag);
  }
}