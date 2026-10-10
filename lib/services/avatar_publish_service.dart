import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../core/supabase/supabase_bootstrap.dart';
import 'contacts_repository.dart';
import 'own_avatar_repository.dart';
import 'signal/hive_signal_protocol_store.dart';
import 'signal/pairing_service.dart';

/// Envia a foto de perfil do usuário, cifrada individualmente por Signal
/// Protocol para CADA contato pareado, pelo mesmo canal Realtime usado
/// pelos momentos do feed (evento diferente: 'avatar' em vez de 'momento').
///
/// Como a [OwnAvatarRepository], isto nunca passa a imagem em texto plano
/// por nenhuma tabela do Supabase — só trafega cifrada, via Broadcast.
class AvatarPublishService {
  AvatarPublishService(this._store);

  final HiveSignalProtocolStore _store;

  Future<void> publishToAllContacts(Uint8List avatarBytes) async {
    final contacts = ContactsRepository.instance.getAll();
    for (final contact in contacts) {
      await _sendToContact(contact.userId, avatarBytes);
    }
  }

  Future<void> _sendToContact(String contactUserId, Uint8List bytes) async {
    final remoteAddress = SignalProtocolAddress(contactUserId, kSignalDeviceId);
    final sessionCipher = SessionCipher(
      _store, // SessionStore
      _store, // PreKeyStore
      _store, // SignedPreKeyStore
      _store, // IdentityKeyStore
      remoteAddress,
    );

    final ciphertext = await sessionCipher.encrypt(bytes);
    final isPreKeyMessage = ciphertext is PreKeySignalMessage;

    final channel = SupabaseBootstrap.client.channel('inbox:$contactUserId');
    channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'avatar',
      payload: {
        'sender_id': SupabaseBootstrap.currentUserId,
        'type': isPreKeyMessage ? 'prekey' : 'signal',
        'body': base64Encode(ciphertext.serialize()),
      },
    );
    await SupabaseBootstrap.client.removeChannel(channel);
  }
}
