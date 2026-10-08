import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_bootstrap.dart';
import '../models/feed_post_hive.dart';
import 'local_feed_repository.dart';
import 'signal/hive_signal_protocol_store.dart';
import 'signal/pairing_service.dart';

/// Requisito 2 do briefing: "Serviço de Sincronização e Recepção em
/// Segundo Plano".
///
/// Cada usuário escuta UM ÚNICO canal Supabase Realtime Broadcast, cujo
/// nome é derivado do seu próprio `auth.uid()` (`inbox:<uid>`). Quem quiser
/// te mandar um momento, transmite (`broadcast`) nesse canal — o Supabase
/// não guarda o payload em tabela nenhuma: Broadcast é fire-and-forget,
/// só entrega a quem estiver com o canal aberto (ou devolve via Push, se
/// configurado — isso fica fora do escopo deste arquivo, que cobre o
/// caminho "app aberto/em segundo plano com o processo Dart vivo").
class RealtimeRelayService {
  RealtimeRelayService(this._store);

  final HiveSignalProtocolStore _store;
  RealtimeChannel? _inboxChannel;

  String get _ownChannelName =>
      'inbox:${SupabaseBootstrap.currentUserId}';

  /// Chamado uma vez no bootstrap (depois de Supabase + Hive + Signal
  /// store prontos). Abre e mantém o canal próprio inscrito.
  Future<void> startListening() async {
    await stopListening();

    _inboxChannel = SupabaseBootstrap.client.channel(_ownChannelName);
    _inboxChannel!
        .onBroadcast(
          event: 'momento',
          callback: (payload) => _handleIncoming(payload),
        )
        .subscribe();
  }

  Future<void> stopListening() async {
    final channel = _inboxChannel;
    if (channel != null) {
      await SupabaseBootstrap.client.removeChannel(channel);
      _inboxChannel = null;
    }
  }

  Future<void> _handleIncoming(Map<String, dynamic> payload) async {
    try {
      final senderId = payload['sender_id'] as String;
      final senderName = payload['sender_name'] as String;
      final senderAvatar = payload['sender_avatar'] as String?;
      final postId = payload['post_id'] as String;
      final publishedAtMs = payload['published_at_ms'] as int;
      final messageType = payload['type'] as String; // 'prekey' | 'signal'
      final body = base64Decode(payload['body'] as String);

      final remoteAddress = SignalProtocolAddress(senderId, kSignalDeviceId);
      // _store implementa as 4 interfaces separadamente (não é um
      // SignalProtocolStore nominal), então usamos o construtor explícito
      // em vez de SessionCipher.fromStore(...).
      final sessionCipher = SessionCipher(
        _store, // SessionStore
        _store, // PreKeyStore
        _store, // SignedPreKeyStore
        _store, // IdentityKeyStore
        remoteAddress,
      );

      final Uint8List plaintext;
      if (messageType == 'prekey') {
        plaintext = await sessionCipher
            .decrypt(PreKeySignalMessage(body));
      } else {
        plaintext = await sessionCipher
            .decryptFromSignal(SignalMessage.fromSerialized(body));
      }

      final decoded = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;

      final post = FeedPostHive.create(
        id: postId,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        payload: jsonEncode(decoded),
        publishedAt: DateTime.fromMillisecondsSinceEpoch(publishedAtMs),
        wasEncryptedInTransit: true,
      );

      await LocalFeedRepository.instance.upsert(post);
    } catch (_) {
      // Pacote corrompido, de um remetente sem sessão válida, ou campo
      // ausente: descartamos silenciosamente. Um relé não deve derrubar
      // o listener do app por causa de 1 pacote ruim.
      return;
    }
  }
}
