import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase/supabase_bootstrap.dart';
import '../models/contact_hive.dart';
import '../models/feed_post_hive.dart';
import 'contacts_repository.dart';
import 'local_feed_repository.dart';
import 'signal/hive_signal_protocol_store.dart';
import 'signal/pairing_service.dart';

/// Publica um "momento" (post efêmero). Importante: isto NÃO é um broadcast
/// público estilo Facebook — é enviado individualmente, com uma cifra
/// Signal diferente, para CADA contato pareado (fan-out ponta a ponta,
/// como o Signal/WhatsApp fazem). Quem não é seu contato direto jamais
/// recebe o pacote, nem cifrado (requisito 2 da filosofia: sem rede
/// além dos contactos diretos).
class FeedPublishService {
  FeedPublishService(this._store);

  final HiveSignalProtocolStore _store;
  final _uuid = const Uuid();

  /// [contentJson] é o mesmo formato usado por [FeedPostHive.payload] —
  /// normalmente um `jsonEncode` dos campos do seu `Post` model existente
  /// (texto, imagens, etc.), para que o lado receptor consiga reconstruir
  /// um `Post` direto na UI sem transformação adicional.
  Future<FeedPostHive> publish({
    required String senderDisplayName,
    String? senderAvatarPath,
    required Map<String, dynamic> contentJson,
  }) async {
    final postId = _uuid.v4();
    final publishedAt = DateTime.now();
    final Uint8List plaintext = Uint8List.fromList(utf8.encode(jsonEncode(contentJson)));

    final contacts = ContactsRepository.instance.getAll();
    for (final contact in contacts) {
      await _sendToContact(
        contact: contact,
        postId: postId,
        publishedAt: publishedAt,
        senderDisplayName: senderDisplayName,
        senderAvatarPath: senderAvatarPath,
        plaintext: plaintext,
      );
    }

    // Guarda também a própria cópia local (para o autor ver seu post no
    // feed), já em claro — não faz sentido autocifrar para si mesmo.
    final ownPost = FeedPostHive.create(
      id: postId,
      senderId: SupabaseBootstrap.currentUserId,
      senderName: senderDisplayName,
      senderAvatar: senderAvatarPath,
      payload: jsonEncode(contentJson),
      publishedAt: publishedAt,
    );
    await LocalFeedRepository.instance.upsert(ownPost);
    return ownPost;
  }

  Future<void> _sendToContact({
    required ContactHive contact,
    required String postId,
    required DateTime publishedAt,
    required String senderDisplayName,
    String? senderAvatarPath,
    required Uint8List plaintext,
  }) async {
    final remoteAddress =
        SignalProtocolAddress(contact.userId, kSignalDeviceId);

    final sessionCipher = SessionCipher(
      _store, // SessionStore
      _store, // PreKeyStore
      _store, // SignedPreKeyStore
      _store, // IdentityKeyStore
      remoteAddress,
    );

    final ciphertext = await sessionCipher.encrypt(plaintext);
    final isPreKeyMessage = ciphertext is PreKeySignalMessage;

    final channel = SupabaseBootstrap.client.channel('inbox:${contact.userId}');
    await channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'momento',
      payload: {
        'sender_id': SupabaseBootstrap.currentUserId,
        'sender_name': senderDisplayName,
        'sender_avatar': senderAvatarPath,
        'post_id': postId,
        'published_at_ms': publishedAt.millisecondsSinceEpoch,
        'type': isPreKeyMessage ? 'prekey' : 'signal',
        'body': base64Encode(ciphertext.serialize()),
      },
    );
    await SupabaseBootstrap.client.removeChannel(channel);
  }
}
