import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Guarda a foto de perfil do PRÓPRIO usuário, localmente, em Hive.
///
/// Não existe upload para nenhum bucket/tabela do Supabase: a imagem em si
/// nunca sai do dispositivo em texto plano. O que é compartilhado com
/// contatos (opcional, ver [AvatarPublishService]) vai cifrado pelo mesmo
/// canal Realtime usado pelos momentos do feed.
class OwnAvatarRepository {
  OwnAvatarRepository._internal();
  static final OwnAvatarRepository instance = OwnAvatarRepository._internal();

  static const _boxName = 'own_avatar_box';
  static const _key = 'bytes';

  Box<Uint8List>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<Uint8List>(_boxName);
  }

  Box<Uint8List> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('OwnAvatarRepository usada antes de init().');
    }
    return box;
  }

  Uint8List? getBytes() => _requireBox.get(_key);

  Future<void> setBytes(Uint8List bytes) async {
    await _requireBox.put(_key, bytes);
  }

  Future<void> clear() async {
    await _requireBox.delete(_key);
  }
}
