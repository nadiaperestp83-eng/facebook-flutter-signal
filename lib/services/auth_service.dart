import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_bootstrap.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Login/cadastro real por e-mail e senha no Supabase Auth. Substitui o
/// auth anônimo usado provisoriamente na Fase 2 — agora a identidade do
/// usuário é estável entre reinstalações/dispositivos (pode logar de novo
/// com o mesmo e-mail), o que o modo anônimo não permitia.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  GoTrueClient get _auth => SupabaseBootstrap.client.auth;

  /// Stream usada pelo AuthGate para decidir entre tela de Login e Home.
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Session? get currentSession => _auth.currentSession;
  bool get isLoggedIn => currentSession != null;

  /// [displayName] é gravado em `user_metadata.full_name` e depois lido
  /// pelo IdentityService para publicar o bundle público do Signal com
  /// esse nome — sem precisar de tabela extra de perfis.
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final res = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': displayName.trim()},
      );
      if (res.user == null) {
        throw AuthException('Não foi possível criar a conta. Tente novamente.');
      }
    } on AuthApiException catch (e) {
      throw AuthException(_translate(e.message));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthApiException catch (e) {
      throw AuthException(_translate(e.message));
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Nome de exibição do usuário logado, usado pelo IdentityService e pelo
  /// FeedPublishService. Cai no e-mail se, por algum motivo, o metadata
  /// não tiver sido gravado (ex: conta criada por outro fluxo).
  String get displayName {
    final user = _auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();
    return user?.email ?? 'Usuário';
  }

  String _translate(String supabaseMessage) {
    final msg = supabaseMessage.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (msg.contains('user already registered')) {
      return 'Já existe uma conta com este e-mail. Tente entrar.';
    }
    if (msg.contains('password should be at least')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }
    if (msg.contains('unable to validate email')) {
      return 'E-mail inválido.';
    }
    return supabaseMessage;
  }
}
