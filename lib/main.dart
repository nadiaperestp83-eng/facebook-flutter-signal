import 'package:facebook/features/home/screens/home_screen.dart';
import 'package:facebook/providers/user_provider.dart';
import 'package:facebook/router.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'constants/global_variables.dart';
import 'controllers/feed_controller.dart';
import 'core/local_storage/hive_boxes.dart';
import 'models/feed_post_hive.dart';
import 'services/feed_expiration_service.dart';
import 'services/local_feed_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Bootstrap do feed efêmero local-first (Hive) ---
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(HiveBoxes.feedPostTypeId)) {
    Hive.registerAdapter(FeedPostHiveAdapter());
  }
  await LocalFeedRepository.instance.init();
  await FeedExpirationService.instance.startup();

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
  // widget visual foi alterado.
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
      home: const HomeScreen(),
    );
  }
}
