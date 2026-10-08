import 'package:facebook/features/auth/widgets/auth_gate.dart';
import 'package:facebook/providers/user_provider.dart';
import 'package:facebook/router.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'constants/global_variables.dart';
import 'controllers/feed_controller.dart';
import 'core/local_storage/hive_boxes.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'models/contact_hive.dart';
import 'models/feed_post_hive.dart';
import 'services/feed_expiration_service.dart';
import 'services/local_feed_repository.dart';
import 'services/signal/hive_signal_protocol_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Hive: feed efêmero + contatos + store do Signal Protocol ---
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(HiveBoxes.feedPostTypeId)) {
    Hive.registerAdapter(FeedPostHiveAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(ContactHiveAdapter());
  }
  await LocalFeedRepository.instance.init();
  await FeedExpirationService.instance.startup();
  await HiveSignalProtocolStore.instance.init();
  // ContactsRepository.instance.init() acontece depois do login, dentro do
  // AuthGate — só faz sentido ter contatos depois de saber quem é o usuário.

  // --- Supabase: só inicializa o client; NENHUM login automático aqui.
  // Quem decide entre tela de Login e Home é o AuthGate, com base em
  // client.auth.onAuthStateChange. ---
  await SupabaseBootstrap.init();

  // Controller fica disponível globalmente via Get.find<FeedController>()
  // em qualquer widget, sem precisar re-instanciar.
  Get.put(FeedController(), permanent: true);

  runApp(MultiProvider(
    providers: [ChangeNotifierProvider(create: (context) => UserProvider())],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Trocamos MaterialApp por GetMaterialApp (drop-in compatível: mesmos
  // parâmetros, mesmo theme, mesmas rotas) apenas para habilitar os
  // recursos reativos do GetX em qualquer parte da árvore. Nenhum
  // widget visual original foi alterado — a única tela nova é a de
  // login/cadastro, pedida explicitamente.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Facebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: GlobalVariables.backgroundColor,
        colorScheme:
            const ColorScheme.light(primary: GlobalVariables.backgroundColor),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          iconTheme: IconThemeData(color: GlobalVariables.iconColor),
        ),
      ),
      onGenerateRoute: (settings) => generateRoute(settings),
      home: const AuthGate(),
    );
  }
}
