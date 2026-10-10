import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Guarda, localmente, as fotos de perfil que os CONTATOS compartilharam
/// com este usuário (recebidas já decifradas via RealtimeRelayService).
///
/// Nenhuma UI usa isso ainda (fora do escopo combinado agora — só o nome e
/// a própria foto). Deixo pronto para quando quiser mostrar a foto real
/// dos contatos em algum lugar (lista de amigos, posts recebidos, etc.).
class ContactAvatarsRepository {
  ContactAvatarsRepository._internal();
  static final ContactAvatarsRepository instance =
      ContactAvatarsRepository._internal();

  static const _boxName = 'contact_avatars_box';

  Box<Uint8List>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<Uint8List>(_boxName);
  }

  Box<Uint8List> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('ContactAvatarsRepository usada antes de init().');
    }
    return box;
  }

  Uint8List? getBytes(String contactUserId) => _requireBox.get(contactUserId);

  Future<void> setBytes(String contactUserId, Uint8List bytes) async {
    await _requireBox.put(contactUserId, bytes);
  }
}
