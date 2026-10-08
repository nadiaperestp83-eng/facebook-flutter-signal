import 'package:hive_flutter/hive_flutter.dart';

import '../core/local_storage/hive_boxes.dart';
import '../models/feed_post_hive.dart';

/// Única porta de entrada/saída para a box Hive do feed efêmero.
///
/// Nenhuma outra classe do app deve chamar `Hive.box(...)` diretamente
/// para o feed — tudo passa por aqui, para mantermos a regra de
/// "zero nuvem / local-first" auditável num único arquivo.
class LocalFeedRepository {
  LocalFeedRepository._internal();
  static final LocalFeedRepository instance = LocalFeedRepository._internal();

  Box<FeedPostHive>? _box;

  bool get isReady => _box != null && _box!.isOpen;

  /// Deve ser chamado uma única vez, após `Hive.initFlutter()` e o
  /// registro do adapter, antes de qualquer leitura/escrita.
  Future<void> init() async {
    if (isReady) return;
    _box = await Hive.openBox<FeedPostHive>(HiveBoxes.feedBox);
  }

  Box<FeedPostHive> get _requireBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError(
        'LocalFeedRepository usada antes de init(). '
        'Chame LocalFeedRepository.instance.init() no bootstrap do app.',
      );
    }
    return box;
  }

  /// Stream bruta de mudanças da box (inserts/updates/deletes), usada pelo
  /// FeedController para reatividade sem precisar de polling.
  Stream<BoxEvent> watch() => _requireBox.watch();

  /// Insere ou substitui um momento recebido (idempotente por [post.id]).
  Future<void> upsert(FeedPostHive post) async {
    await _requireBox.put(post.id, post);
  }

  Future<void> upsertAll(Iterable<FeedPostHive> posts) async {
    final map = {for (final p in posts) p.id: p};
    await _requireBox.putAll(map);
  }

  /// Remove um momento específico (ex: o remetente apagou/revogou).
  Future<void> delete(String id) async {
    await _requireBox.delete(id);
  }

  /// Retorna todos os momentos ainda válidos, em ordem estritamente
  /// cronológica decrescente (mais recente primeiro). Nenhum critério de
  /// relevância/engajamento é aplicado — é por isso que não há "sort by
  /// score" em lugar nenhum deste repositório.
  List<FeedPostHive> getActiveChronological() {
    final now = DateTime.now();
    final values = _requireBox.values.where((p) => p.expiresAt.isAfter(now)).toList();
    values.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return values;
  }

  /// Varre a box inteira e apaga tudo que já passou de 24h.
  /// Retorna quantos itens foram removidos (útil para logs/telemetria local).
  Future<int> purgeExpired() async {
    final box = _requireBox;
    final now = DateTime.now();
    final expiredKeys = box.keys.where((key) {
      final post = box.get(key);
      return post == null || post.expiresAt.isBefore(now);
    }).toList();

    if (expiredKeys.isEmpty) return 0;
    await box.deleteAll(expiredKeys);
    return expiredKeys.length;
  }

  Future<void> clearAll() async {
    await _requireBox.clear();
  }
}
