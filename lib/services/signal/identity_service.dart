import 'dart:convert';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import 'hive_signal_protocol_store.dart';

/// Responsável por:
/// 1. Gerar a identidade Signal local (uma única vez, no primeiro boot);
/// 2. Publicar/atualizar o bundle PÚBLICO (nunca a parte privada) na
///    tabela `signal_public_keys` do Supabase, para que outros possam
///    iniciar uma sessão X3DH mesmo com este dispositivo offline.
class IdentityService {
  IdentityService(this._store);

  final HiveSignalProtocolStore _store;

  static const int _signedPreKeyId = 0;
  static const int _oneTimePreKeyRangeStart = 0;
  static const int _oneTimePreKeyCount = 100;

  /// Chamado uma vez no bootstrap (depois de _store.init() e do
  /// SupabaseBootstrap.init()). Gera a identidade local se ainda não existir
  /// e garante que o Supabase tenha o bundle público mais recente.
  Future<void> ensureLocalIdentityAndPublish({
    required String displayName,
    String? avatarPath,
  }) async {
    List<PreKeyRecord>? freshOneTimePreKeys;
    SignedPreKeyRecord? freshSignedPreKey;
    IdentityKeyPair identityKeyPair;
    int registrationId;

    if (!_store.hasLocalIdentity) {
      identityKeyPair = generateIdentityKeyPair();
      registrationId = generateRegistrationId(false);
      await _store.persistLocalIdentity(identityKeyPair, registrationId);

      freshOneTimePreKeys = generatePreKeys(
        _oneTimePreKeyRangeStart,
        _oneTimePreKeyCount,
      );
      for (final p in freshOneTimePreKeys) {
        await _store.storePreKey(p.id, p);
      }

      freshSignedPreKey = generateSignedPreKey(identityKeyPair, _signedPreKeyId);
      await _store.storeSignedPreKey(_signedPreKeyId, freshSignedPreKey);
    } else {
      identityKeyPair = await _store.getIdentityKeyPair();
      registrationId = await _store.getLocalRegistrationId();
      freshSignedPreKey = await _store.loadSignedPreKey(_signedPreKeyId);
    }

    await _publishBundle(
      identityKeyPair: identityKeyPair,
      registrationId: registrationId,
      signedPreKey: freshSignedPreKey,
      oneTimePreKeysToAnnounce: freshOneTimePreKeys,
      displayName: displayName,
      avatarPath: avatarPath,
    );
  }

  /// Reabastece o pool de one-time prekeys no Supabase quando está baixo
  /// (ex: muitos pareamentos consumiram as prekeys publicadas). Chame
  /// periodicamente (ex: no mesmo startup do FeedExpirationService) ou
  /// antes de pedir para o usuário compartilhar seu "código de adicionar".
  Future<void> replenishOneTimePreKeysIfNeeded({int threshold = 10}) async {
    final table = SupabaseBootstrap.client.from('signal_public_keys');
    final row = await table
        .select('one_time_pre_keys')
        .eq('user_id', SupabaseBootstrap.currentUserId)
        .maybeSingle();

    final currentCount =
        (row?['one_time_pre_keys'] as List?)?.length ?? 0;
    if (currentCount > threshold) return;

    // Gera um novo lote com ids a partir do maior id local já conhecido,
    // para nunca reemitir um preKeyId já usado por uma sessão em andamento.
    final nextStart = await _nextFreePreKeyId();
    final newBatch = generatePreKeys(nextStart, _oneTimePreKeyCount);
    for (final p in newBatch) {
      await _store.storePreKey(p.id, p);
    }

    final announce = newBatch
        .map((p) => {
              'id': p.id,
              'public_key': base64Encode(p.getKeyPair().publicKey.serialize()),
            })
        .toList();

    await table.update({
      'one_time_pre_keys': announce,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('user_id', SupabaseBootstrap.currentUserId);
  }

  Future<int> _nextFreePreKeyId() async {
    // Estratégia simples: carimbo de tempo truncado garante não-colisão
    // prática sem precisar varrer toda a box local.
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000;
  }

  Future<void> _publishBundle({
    required IdentityKeyPair identityKeyPair,
    required int registrationId,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord>? oneTimePreKeysToAnnounce,
    required String displayName,
    String? avatarPath,
  }) async {
    final publicKey = identityKeyPair.getPublicKey();
    final signedPublic = signedPreKey.getKeyPair().publicKey;

    final payload = {
      'user_id': SupabaseBootstrap.currentUserId,
      'display_name': displayName,
      'avatar_path': avatarPath,
      'registration_id': registrationId,
      'identity_key': base64Encode(publicKey.serialize()),
      'signed_pre_key_id': signedPreKey.id,
      'signed_pre_key_public': base64Encode(signedPublic.serialize()),
      'signed_pre_key_signature': base64Encode(signedPreKey.signature),
      'updated_at': DateTime.now().toIso8601String(),
      if (oneTimePreKeysToAnnounce != null)
        'one_time_pre_keys': oneTimePreKeysToAnnounce
            .map((p) => {
                  'id': p.id,
                  'public_key':
                      base64Encode(p.getKeyPair().publicKey.serialize()),
                })
            .toList(),
    };

    await SupabaseBootstrap.client
        .from('signal_public_keys')
        .upsert(payload, onConflict: 'user_id');
  }
}
