import 'package:hive/hive.dart';

import '../core/local_storage/hive_boxes.dart';

/// Representa um post/momento efêmero do feed, persistido localmente no Hive.
///
/// IMPORTANTE sobre o campo [payload]:
/// - Na Fase 1 (atual), ele guarda o conteúdo em texto plano serializado
///   em JSON (compatível com o modelo [Post] da UI existente), pois ainda
///   não existe camada de transporte/criptografia.
/// - Na Fase 2 (Signal Protocol + Supabase Realtime), ele passará a guardar
///   o ciphertext (Base64) já decifrado localmente no momento da recepção —
///   ou seja, o que entra na Hive já está em texto plano para a UI consumir;
///   o que trafega pela rede é que vem cifrado. [isEncryptedAtRest] continua
///   false porque não duplicamos a cifra no disco: decidimos a favor de
///   "decifrar uma vez, guardar local em claro, confiar no sandboxing do SO".
///   Se quiser cifrar também em repouso (ameaça = dispositivo comprometido/
///   forense), me avise para adicionarmos uma chave local (ex: via
///   flutter_secure_storage) e um HiveAesCipher na abertura da box.
class FeedPostHive extends HiveObject {
  /// Identificador único do momento (UUID v4, gerado no dispositivo de origem).
  final String id;

  /// Identificador estável do remetente (ex: identityKey público do Signal,
  /// ou, na Fase 1, apenas um nome/alias local).
  final String senderId;

  /// Nome de exibição do remetente, para render imediato sem precisar
  /// resolver contato.
  final String senderName;

  /// Avatar do remetente (path de asset local ou URL, conforme o app usa hoje).
  final String? senderAvatar;

  /// Conteúdo do post já pronto para a UI (texto, pode conter um JSON
  /// serializado de campos extras como imagens/vídeos — ver [FeedPostHive.toPostFields]).
  final String payload;

  /// Momento em que o post foi publicado pelo remetente original.
  final DateTime publishedAt;

  /// Momento de expiração automática (sempre publishedAt + 24h).
  final DateTime expiresAt;

  /// Marca se o conteúdo chegou cifrado (Fase 2) ou em texto plano (Fase 1).
  final bool wasEncryptedInTransit;

  FeedPostHive({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.payload,
    required this.publishedAt,
    required this.expiresAt,
    this.senderAvatar,
    this.wasEncryptedInTransit = false,
  });

  /// Fábrica de conveniência: cria já calculando a expiração em +24h.
  factory FeedPostHive.create({
    required String id,
    required String senderId,
    required String senderName,
    required String payload,
    String? senderAvatar,
    DateTime? publishedAt,
    bool wasEncryptedInTransit = false,
  }) {
    final published = publishedAt ?? DateTime.now();
    return FeedPostHive(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      payload: payload,
      publishedAt: published,
      expiresAt: published.add(const Duration(hours: 24)),
      wasEncryptedInTransit: wasEncryptedInTransit,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeUntilExpiration => expiresAt.difference(DateTime.now());
}

/// TypeAdapter escrito manualmente (sem build_runner) para
/// [FeedPostHive]. Isso evita dependência de codegen no pipeline do
/// usuário e deixa explícito, campo a campo, o que é persistido.
class FeedPostHiveAdapter extends TypeAdapter<FeedPostHive> {
  @override
  final int typeId = HiveBoxes.feedPostTypeId;

  @override
  FeedPostHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FeedPostHive(
      id: fields[0] as String,
      senderId: fields[1] as String,
      senderName: fields[2] as String,
      senderAvatar: fields[3] as String?,
      payload: fields[4] as String,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(fields[5] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(fields[6] as int),
      wasEncryptedInTransit: (fields[7] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, FeedPostHive obj) {
    writer
      ..writeByte(8) // número de campos
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.senderId)
      ..writeByte(2)
      ..write(obj.senderName)
      ..writeByte(3)
      ..write(obj.senderAvatar)
      ..writeByte(4)
      ..write(obj.payload)
      ..writeByte(5)
      ..write(obj.publishedAt.millisecondsSinceEpoch)
      ..writeByte(6)
      ..write(obj.expiresAt.millisecondsSinceEpoch)
      ..writeByte(7)
      ..write(obj.wasEncryptedInTransit);
  }
}
