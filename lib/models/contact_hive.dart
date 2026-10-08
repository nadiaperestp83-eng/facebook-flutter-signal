import 'package:hive/hive.dart';

/// Um contato = alguém com quem já existe (ou está sendo construída) uma
/// sessão Signal. O `userId` é o `auth.uid()` do Supabase (só serve para
/// localizar o canal Realtime e o bundle de chaves públicas — nunca para
/// guardar conteúdo).
class ContactHive extends HiveObject {
  final String userId;
  final String displayName;
  final String? avatarPath;
  final DateTime addedAt;

  ContactHive({
    required this.userId,
    required this.displayName,
    required this.addedAt,
    this.avatarPath,
  });
}

class ContactHiveAdapter extends TypeAdapter<ContactHive> {
  @override
  final int typeId = 2; // reservado na faixa 0-9 junto do FeedPostHive (1)

  @override
  ContactHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContactHive(
      userId: fields[0] as String,
      displayName: fields[1] as String,
      avatarPath: fields[2] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(fields[3] as int),
    );
  }

  @override
  void write(BinaryWriter writer, ContactHive obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.displayName)
      ..writeByte(2)
      ..write(obj.avatarPath)
      ..writeByte(3)
      ..write(obj.addedAt.millisecondsSinceEpoch);
  }
}
