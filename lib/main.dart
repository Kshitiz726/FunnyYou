import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'services/api_config.dart';
import 'services/service_locator.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-only: every screen is designed for vertical, one-handed use.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  ApiConfig.debugLogConfig();

  // Previously generated style previews load from disk before first paint, so
  // returning users never see the placeholder artwork flash.
  await ServiceLocator.instance.previewStore.load();

  final state = await AppState.load();
  runApp(FunnyYouApp(state: state));
}
