/// Registro central de nomes de Box e TypeIds do Hive.
///
/// Mantemos tudo num único lugar para que, ao adicionarmos novos modelos
/// (ex: chaves de sessão do Signal Protocol na Fase 2), não haja colisão
/// de typeId nem strings de box duplicadas espalhadas pelo projeto.
class HiveBoxes {
  HiveBoxes._();

  /// Box que guarda os posts/momentos efêmeros do feed (TTL 24h).
  static const String feedBox = 'local_feed_box';

  /// TypeId reservado para [FeedPostHive].
  /// Reserve 0-9 para modelos de feed; 10-19 ficará reservado para o
  /// armazenamento de sessões/chaves do Signal Protocol (Fase 2).
  static const int feedPostTypeId = 1;
}
