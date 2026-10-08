import 'package:facebook/features/auth/screens/login_screen.dart';
import 'package:facebook/features/home/screens/home_screen.dart';
import 'package:facebook/services/auth_service.dart';
import 'package:facebook/services/contacts_repository.dart';
import 'package:facebook/services/realtime_relay_service.dart';
import 'package:facebook/services/signal/hive_signal_protocol_store.dart';
import 'package:facebook/services/signal/identity_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Porta de entrada do app. Ouve `AuthService.onAuthStateChange` e decide:
///   - sem sessão -> [LoginScreen]
///   - com sessão -> [HomeScreen] (depois de publicar a identidade Signal
///     e abrir o canal Realtime próprio, uma única vez por sessão).
///
/// Nenhum widget visual de HomeScreen/LoginScreen foi alterado — este
/// arquivo só decide QUAL dos dois mostrar.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _bootstrappedForUserId;
  bool _bootstrapInFlight = false;
  String? _bootstrapError;

  Future<void> _bootstrapAfterLogin(String userId) async {
    if (_bootstrappedForUserId == userId || _bootstrapInFlight) return;
    _bootstrapInFlight = true;
    try {
      final identityService = IdentityService(HiveSignalProtocolStore.instance);
      await identityService.ensureLocalIdentityAndPublish(
        displayName: AuthService.instance.displayName,
      );
      await RealtimeRelayService(HiveSignalProtocolStore.instance)
          .startListening();
      await ContactsRepository.instance.init();
      _bootstrappedForUserId = userId;
      _bootstrapError = null;
    } catch (e) {
      _bootstrapError =
          'Não foi possível preparar sua identidade segura: $e';
    } finally {
      _bootstrapInFlight = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? AuthService.instance.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        if (_bootstrappedForUserId != session.user.id) {
          // Dispara o bootstrap (não bloqueia a build, mas mostra um
          // spinner simples enquanto a identidade local é preparada —
          // isso só acontece 1x por sessão, geralmente < 1s).
          _bootstrapAfterLogin(session.user.id);
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: _bootstrapError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _bootstrapError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }

        return const HomeScreen();
      },
    );
  }
}
