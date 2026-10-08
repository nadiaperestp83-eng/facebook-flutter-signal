import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstrap do Supabase, usado SOMENTE como:
///   1. Auth anônima (identidade estável do dispositivo, sem tela de login);
///   2. Tabela mínima `signal_public_keys` (chaves públicas de pareamento);
///   3. Realtime Broadcast (relé volátil, não persistido) para entregar
///      pacotes cifrados do Signal Protocol.
///
/// Nenhum post, momento ou metadado social passa por aqui além das chaves
/// públicas acima — ver sql/001_public_keys.sql para o único schema.
class SupabaseBootstrap {
  SupabaseBootstrap._();

  // TODO: substitua pelas credenciais do seu projeto Supabase
  // (Project Settings > API). A anonKey é pública por design do Supabase,
  // mas nunca coloque a service_role key no app.
  static const String supabaseUrl = 'https://SEU-PROJETO.supabase.co';
  static const String supabaseAnonKey = 'SUA_ANON_KEY_AQUI';

  static SupabaseClient get client => Supabase.instance.client;

  /// Chamado uma vez no bootstrap do app (main.dart), depois do Hive.
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // Sem GoTrue persistSession customizado: o padrão já persiste a
      // sessão localmente, então a identidade anônima sobrevive a
      // reaberturas do app no mesmo dispositivo.
    );

    // Garante uma identidade anônima estável sem exigir nenhuma tela de
    // login — o usuário já tem um "perfil" local (UserProvider); apenas
    // amarramos esse perfil a um auth.uid() estável no Supabase.
    final session = client.auth.currentSession;
    if (session == null) {
      await client.auth.signInAnonymously();
    }
  }

  /// uid estável do dispositivo/usuário atual. Lança se chamado antes do
  /// signInAnonymously completar (não deve acontecer se init() foi aguardado).
  static String get currentUserId {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'SupabaseBootstrap.init() precisa terminar (signInAnonymously) '
        'antes de acessar currentUserId.',
      );
    }
    return user.id;
  }
}
