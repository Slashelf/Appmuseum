import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'chat/chat_controller.dart';
import 'chat/connection_check.dart';
import 'chat/conversation_store.dart';
import 'chat/guide_secrets.dart';
import 'chat/local_guide_answer_service.dart';
import 'chat/local_knowledge_source.dart';
import 'chat/remote_guide_answer_service.dart';
import 'chat/visit_context.dart';
import 'core/locale/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'data/content_repository.dart';
import 'data/local/app_database.dart';
import 'data/local/json_seeder.dart';
import 'data/local_content_repository.dart';
import 'repositories/data_repository.dart';
import 'screens/app_localizations.dart';
import 'screens/beacon_scan_services.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeController = LocaleController();
  await localeController.load();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (error) {
    debugPrint('Firebase no disponible: $error');
  }

  final database = await AppDatabase.open();
  try {
    await JsonSeeder(database).seedIfNeeded();
  } catch (error) {
    debugPrint('No se pudo preparar la base local: $error');
  }

  final ContentRepository repository = LocalContentRepository(database);
  DataRepository.bind(repository);

  final visitContext = VisitContext();
  BeaconServiceFlutter().addPlaceListener(visitContext.updatePlace);
  const xaiKey = String.fromEnvironment('XAI_API_KEY');
  final localAnswers = LocalGuideAnswerService();
  final chat = ChatController(
    store: MemoryConversationStore(),
    knowledge: LocalKnowledgeSource(repository),
    answers: localAnswers,
    remote: RemoteGuideAnswerService(
      apiKey: xaiKey,
      fallback: localAnswers,
    ),
    visit: visitContext,
    compiledKey: xaiKey,
    secrets: SecureGuideSecretStore(),
    connections: HttpConnectionChecker(),
  );
  await chat.restoreSaved();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeController),
        Provider<ContentRepository>.value(value: repository),
        ChangeNotifierProvider<VisitContext>.value(value: visitContext),
        ChangeNotifierProvider<ChatController>.value(value: chat),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().locale;
    return MaterialApp(
      title: 'Guía QR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: locale,
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
        Locale('de'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppLocalizations.delegate,
      ],
      home: const OnBoarding(),
    );
  }
}
