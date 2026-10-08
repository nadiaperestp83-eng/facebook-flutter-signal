import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact_hive.dart';

/// A "rede de contactos direta" do usuário (requisito 2 da filosofia:
/// sem algoritmo, sem descoberta por terceiros — só quem foi pareado
/// manualmente via Signal Protocol entra aqui).
class ContactsRepository {
  ContactsRepository._internal();
  static final ContactsRepository instance = ContactsRepository._internal();

  static const _boxName = 'contacts_box';
  Box<ContactHive>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<ContactHive>(_boxName);
  }

  Box<ContactHive> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('ContactsRepository usada antes de init().');
    }
    return box;
  }

  bool isContact(String userId) => _requireBox.containsKey(userId);

  List<ContactHive> getAll() => _requireBox.values.toList()
    ..sort((a, b) => a.displayName.compareTo(b.displayName));

  Future<void> add(ContactHive contact) async {
    await _requireBox.put(contact.userId, contact);
  }

  Future<void> remove(String userId) async {
    await _requireBox.delete(userId);
  }
}
