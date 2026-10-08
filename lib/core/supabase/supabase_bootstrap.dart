import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstrap do Supabase, usado SOMENTE como:
///   1. Auth por e-mail/senha (tela de login/cadastro em
///      lib/features/auth/screens/login_screen.dart);
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
  /// NÃO faz login nenhum — isso agora é responsabilidade exclusiva da
  /// tela de login/cadastro (AuthService + LoginScreen), decidida pelo
  /// AuthGate a partir de `client.auth.onAuthStateChange`.
  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // O padrão do supabase_flutter já persiste a sessão localmente
      // (via o próprio GoTrue), então um login feito uma vez sobrevive a
      // reaberturas do app no mesmo dispositivo, sem precisar logar de novo.
    );
  }

  /// uid estável do usuário logado. Lança se chamado sem sessão ativa —
  /// todo o código da Fase 2/3 que usa isto só roda depois do AuthGate
  /// confirmar sessão válida, então isso não deve acontecer em uso normal.
  static String get currentUserId {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'Nenhum usuário logado. currentUserId só pode ser usado depois '
        'do login (ver AuthGate).',
      );
    }
    return user.id;
  }
}
