import 'dart:convert';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import '../../models/contact_hive.dart';
import '../contacts_repository.dart';
import 'hive_signal_protocol_store.dart';

/// ID de device fixo (1) para todas as sessões — este app ainda não
/// suporta múltiplos dispositivos por usuário. Se você quiser multi-device
/// depois, isso vira dinâmico por instalação.
const int kSignalDeviceId = 1;

class PairingException implements Exception {
  PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lógica real por trás do botão "Adicionar"/"Thêm bạn bè" do seu fork.
/// Nenhuma UI nova é criada aqui — isso só é chamado a partir do
/// `onPressed` já existente no FriendsSuggestScreen/FriendsScreen.
class PairingService {
  PairingService(this._store);

  final HiveSignalProtocolStore _store;

  /// Pareia com outro usuário a partir do `userId` (auth.uid() dele no
  /// Supabase) — por exemplo, obtido de um link de convite, QR code ou
  /// busca por nome na tela de amigos existente.
  ///
  /// Ao final: sessão Signal pronta (X3DH concluído) + contato salvo
  /// localmente no Hive. Não existe "pedido de amizade" pendente em
  /// servidor algum — o pareamento é imediato e unilateral (como uma
  /// chave pública de SSH): a outra pessoa só passa a te "ver" quando
  /// também parear de volta com o seu userId.
  Future<ContactHive> pairWithUser(String targetUserId) async {
    final table = SupabaseBootstrap.client.from('signal_public_keys');
    final row = await table
        .select()
        .eq('user_id', targetUserId)
        .maybeSingle();

    if (row == null) {
      throw PairingException(
        'Este usuário ainda não publicou suas chaves públicas '
        '(provavelmente nunca abriu o app).',
      );
    }

    // Consome atomicamente UMA one-time prekey (nunca reutilizada entre
    // pareamentos concorrentes) via RPC definida em sql/001_public_keys.sql.
    final consumed = await SupabaseBootstrap.client
        .rpc('consume_one_time_prekey', params: {'target_user_id': targetUserId});

    final registrationId = row['registration_id'] as int;
    final identityKeyBytes = base64Decode(row['identity_key'] as String);
    final identityKey = IdentityKey.fromBytes(identityKeyBytes, 0);

    final signedPreKeyId = row['signed_pre_key_id'] as int;
    final signedPreKeyPublicBytes =
        base64Decode(row['signed_pre_key_public'] as String);
    final signedPreKeyPublic = Curve.decodePoint(signedPreKeyPublicBytes, 0);
    final signedPreKeySignature =
        base64Decode(row['signed_pre_key_signature'] as String);

    int? oneTimePreKeyId;
    ECPublicKey? oneTimePreKeyPublic;
    if (consumed != null) {
      oneTimePreKeyId = consumed['id'] as int;
      oneTimePreKeyPublic =
          Curve.decodePoint(base64Decode(consumed['public_key'] as String), 0);
    }

    final bundle = PreKeyBundle(
      registrationId,
      kSignalDeviceId,
      oneTimePreKeyId,
      oneTimePreKeyPublic,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      identityKey,
    );

    final remoteAddress = SignalProtocolAddress(targetUserId, kSignalDeviceId);
    final sessionBuilder = SessionBuilder(
      _store, // SessionStore
      _store, // PreKeyStore
      _store, // SignedPreKeyStore
      _store, // IdentityKeyStore
      remoteAddress,
    );

    try {
      await sessionBuilder.processPreKeyBundle(bundle);
    } on UntrustedIdentityException {
      throw PairingException(
        'A chave de identidade deste contato mudou desde o último '
        'pareamento. Isso pode indicar reinstalação do app dele OU um '
        'ataque — confirme por outro canal antes de continuar.',
      );
    }

    final contact = ContactHive(
      userId: targetUserId,
      displayName: row['display_name'] as String,
      avatarPath: row['avatar_path'] as String?,
      addedAt: DateTime.now(),
    );
    await ContactsRepository.instance.add(contact);
    return contact;
  }

  Future<void> removeContact(String userId) async {
    final remoteAddress = SignalProtocolAddress(userId, kSignalDeviceId);
    await _store.deleteSession(remoteAddress);
    await ContactsRepository.instance.remove(userId);
  }
}
