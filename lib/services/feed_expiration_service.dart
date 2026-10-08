import 'dart:async';

import '../services/local_feed_repository.dart';

/// Mecanismo de ciclo de vida do conteúdo (requisito 3 do briefing).
///
/// Responsabilidades:
/// 1. Rodar uma varredura imediata ao iniciar o app (cold start).
/// 2. Rodar uma varredura periódica enquanto o app está em foreground,
///    para que posts expirem da tela mesmo sem o usuário reabrir o app.
///
/// Observação sobre background real (app fechado): Hive só pode ser
/// acessado com o processo Dart vivo. Para expirar com o app 100% fechado
/// seria necessário um Workmanager/BGTaskScheduler nativo — isso é um
/// adendo opcional de plataforma, não parte do core local-first, e posso
/// adicionar depois se você quiser (ele só chamaria este mesmo serviço).
class FeedExpirationService {
  FeedExpirationService._internal();
  static final FeedExpirationService instance = FeedExpirationService._internal();

  Timer? _periodicTimer;

  /// Intervalo de varredura em foreground. 15 min é suficiente para um
  /// TTL de 24h sem gastar bateria à toa.
  static const Duration sweepInterval = Duration(minutes: 15);

  /// Chamado uma vez no bootstrap do app, depois de
  /// `LocalFeedRepository.instance.init()`.
  Future<void> startup() async {
    await _sweepOnce();
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(sweepInterval, (_) => _sweepOnce());
  }

  Future<int> _sweepOnce() {
    return LocalFeedRepository.instance.purgeExpired();
  }

  /// Permite disparar uma varredura manual (ex: puxar para atualizar o feed).
  Future<int> sweepNow() => _sweepOnce();

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
