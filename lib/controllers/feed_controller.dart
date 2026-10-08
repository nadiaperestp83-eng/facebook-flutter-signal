import 'dart:async';

import 'package:get/get.dart';

import '../models/feed_post_hive.dart';
import '../services/feed_expiration_service.dart';
import '../services/local_feed_repository.dart';

/// Controller reativo (GetX) do feed efêmero.
///
/// Regra de ouro deste arquivo: NENHUMA linha aqui decide "o que o usuário
/// quer ver" — a única ordenação permitida é cronológica decrescente,
/// delegada ao [LocalFeedRepository.getActiveChronological]. Não há score,
/// não há "posts relevantes", não há priorização de terceiros.
class FeedController extends GetxController {
  final RxList<FeedPostHive> posts = <FeedPostHive>[].obs;
  final RxBool isLoading = false.obs;

  StreamSubscription? _boxSubscription;

  @override
  void onInit() {
    super.onInit();
    _loadFromHive();
    _listenToHiveChanges();
  }

  @override
  void onClose() {
    _boxSubscription?.cancel();
    super.onClose();
  }

  void _loadFromHive() {
    isLoading.value = true;
    posts.assignAll(LocalFeedRepository.instance.getActiveChronological());
    isLoading.value = false;
  }

  /// Reage a qualquer escrita na box do Hive (chegada de novo momento via
  /// Supabase Realtime, expiração removendo um item, etc.) sem precisar de
  /// polling manual na UI.
  void _listenToHiveChanges() {
    _boxSubscription = LocalFeedRepository.instance.watch().listen((_) {
      _loadFromHive();
    });
  }

  /// Puxar para atualizar: força uma varredura de expiração e recarrega.
  /// Não busca nada em nuvem — só reflete o estado atual do Hive local.
  Future<void> refresh() async {
    await FeedExpirationService.instance.sweepNow();
    _loadFromHive();
  }

  bool get isEmpty => posts.isEmpty;
}
