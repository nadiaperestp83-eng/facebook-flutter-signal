import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Implementação persistente (Hive) das 4 interfaces que o
/// libsignal_protocol_dart exige para operar: [IdentityKeyStore],
/// [PreKeyStore], [SignedPreKeyStore] e [SessionStore].
///
/// Tudo fica em bytes serializados (cada classe do libsignal já expõe
/// `.serialize()` / `.fromSerialized()` / `.fromBuffer()`), guardados em
/// boxes Hive dedicadas. Nada disto nunca sai do dispositivo: é a parte
/// "privada" do par de chaves que NUNCA é enviada ao Supabase — só as
/// chaves públicas (ver IdentityService) vão para a tabela `signal_public_keys`.
///
/// Importante: diferente do `InMemory*Store` que vem de fábrica na lib
/// (mencionado na doc oficial como "NÃO sobrevive a restart"), esta classe
/// é a store persistente real que o projeto precisa.
class HiveSignalProtocolStore
    implements
        IdentityKeyStore,
        PreKeyStore,
        SignedPreKeyStore,
        SessionStore {
  static const _identityBoxName = 'signal_identity_box';
  static const _preKeyBoxName = 'signal_prekey_box';
  static const _signedPreKeyBoxName = 'signal_signed_prekey_box';
  static const _sessionBoxName = 'signal_session_box';
  static const _trustedIdentitiesBoxName = 'signal_trusted_identities_box';

  static const _kIdentityKeyPair = 'identity_key_pair';
  static const _kRegistrationId = 'registration_id';

  late Box<Uint8List> _identityBox; // guarda o par de chaves + registrationId
  late Box<Uint8List> _preKeyBox; // key: preKeyId (string)
  late Box<Uint8List> _signedPreKeyBox; // key: signedPreKeyId (string)
  late Box<Uint8List> _sessionBox; // key: "name.deviceId"
  late Box<String> _trustedIdentitiesBox; // key: "name.deviceId" -> base64

  bool _ready = false;

  /// Deve ser chamado uma vez no bootstrap, ANTES de gerar/usar qualquer
  /// identidade (ver IdentityService).
  Future<void> init() async {
    if (_ready) return;
    _identityBox = await Hive.openBox<Uint8List>(_identityBoxName);
    _preKeyBox = await Hive.openBox<Uint8List>(_preKeyBoxName);
    _signedPreKeyBox = await Hive.openBox<Uint8List>(_signedPreKeyBoxName);
    _sessionBox = await Hive.openBox<Uint8List>(_sessionBoxName);
    _trustedIdentitiesBox =
        await Hive.openBox<String>(_trustedIdentitiesBoxName);
    _ready = true;
  }

  bool get hasLocalIdentity => _identityBox.containsKey(_kIdentityKeyPair);

  /// Usado pelo IdentityService na primeira execução do app, para gravar
  /// a identidade recém-gerada.
  Future<void> persistLocalIdentity(
    IdentityKeyPair keyPair,
    int registrationId,
  ) async {
    await _identityBox.put(_kIdentityKeyPair, keyPair.serialize());
    await _identityBox.put(
      _kRegistrationId,
      Uint8List(4)..buffer.asByteData().setInt32(0, registrationId),
    );
  }

  String _addressKey(SignalProtocolAddress address) =>
      '${address.getName()}.${address.getDeviceId()}';

  // ---------------- IdentityKeyStore ----------------

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final bytes = _identityBox.get(_kIdentityKeyPair);
    if (bytes == null) {
      throw StateError(
        'Identidade local ainda não foi gerada. Chame IdentityService.ensureLocalIdentity() antes.',
      );
    }
    return IdentityKeyPair.fromSerialized(bytes);
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final bytes = _identityBox.get(_kRegistrationId);
    if (bytes == null) {
      throw StateError('registrationId local ainda não foi gerado.');
    }
    return bytes.buffer.asByteData().getInt32(0);
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final b64 = _trustedIdentitiesBox.get(_addressKey(address));
    if (b64 == null) return null;
    return IdentityKey.fromBytes(base64DecodeBytes(b64), 0);
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final key = _addressKey(address);
    final existing = _trustedIdentitiesBox.get(key);
    final encoded = base64EncodeBytes(identityKey.serialize());
    final changed = existing != null && existing != encoded;
    await _trustedIdentitiesBox.put(key, encoded);
    return changed;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    // TOFU (Trust On First Use) — igual ao comportamento padrão do Signal:
    // a primeira chave vista para um contato é confiada automaticamente;
    // uma mudança posterior (possível MITM ou reinstalação do contato)
    // precisaria de uma re-verificação manual, que fica fora do escopo
    // desta Fase 2 (poderia virar um "número de segurança" na UI depois).
    final known = await getIdentity(address);
    if (known == null) return true;
    return identityKey != null && known.serialize().toString() == identityKey.serialize().toString();
  }

  // ---------------- PreKeyStore ----------------

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      _preKeyBox.containsKey(preKeyId.toString());

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final bytes = _preKeyBox.get(preKeyId.toString());
    if (bytes == null) {
      throw StateError('Nenhuma preKey local com id $preKeyId');
    }
    return PreKeyRecord.fromBuffer(bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _preKeyBox.put(preKeyId.toString(), record.serialize());
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _preKeyBox.delete(preKeyId.toString());
  }

  // ---------------- SignedPreKeyStore ----------------

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      _signedPreKeyBox.containsKey(signedPreKeyId.toString());

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = _signedPreKeyBox.get(signedPreKeyId.toString());
    if (bytes == null) {
      throw StateError(
          'Nenhuma signedPreKey local com id $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(bytes);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    return _signedPreKeyBox.values
        .map((bytes) => SignedPreKeyRecord.fromSerialized(bytes))
        .toList();
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    await _signedPreKeyBox.put(signedPreKeyId.toString(), record.serialize());
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _signedPreKeyBox.delete(signedPreKeyId.toString());
  }

  // ---------------- SessionStore ----------------

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      _sessionBox.containsKey(_addressKey(address));

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final bytes = _sessionBox.get(_addressKey(address));
    if (bytes == null) return SessionRecord();
    return SessionRecord.fromSerialized(bytes);
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    await _sessionBox.put(_addressKey(address), record.serialize());
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await _sessionBox.delete(_addressKey(address));
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    final keys =
        _sessionBox.keys.where((k) => (k as String).startsWith('$name.'));
    await _sessionBox.deleteAll(keys);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    return _sessionBox.keys
        .cast<String>()
        .where((k) => k.startsWith('$name.'))
        .map((k) => int.parse(k.split('.').last))
        .toList();
  }
}

// Helpers de (de)serialização base64, usados para guardar a chave pública
// confiada de um contato (IdentityKey) como string dentro do Hive.
Uint8List base64DecodeBytes(String s) => base64Decode(s);

String base64EncodeBytes(Uint8List bytes) => base64Encode(bytes);
