import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/app_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = AppSession.I;
  await session.init();
  runApp(JshDashboardApp(session: session));
}
