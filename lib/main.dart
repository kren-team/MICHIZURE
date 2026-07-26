import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrapState = await AppBootstrap(
    settings: currentFirebaseBootstrapSettings(),
    firebaseGateway: FlutterFireGateway(),
  ).run();

  runApp(MichizureApp(bootstrapState: bootstrapState));
}
