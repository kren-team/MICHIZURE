import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'features/notifications/infrastructure/firebase_messaging_background_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrapState = await AppBootstrap(
    settings: currentFirebaseBootstrapSettings(),
    firebaseGateway: FlutterFireGateway(),
  ).run();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(MichizureApp(bootstrapState: bootstrapState));
}
