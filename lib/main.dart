import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'features/notifications/infrastructure/firebase_messaging_background_handler.dart';
import 'features/notifications/infrastructure/flutter_local_notification_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrapState = await AppBootstrap(
    settings: currentFirebaseBootstrapSettings(),
    firebaseGateway: FlutterFireGateway(),
  ).run();

  await defaultLocalNotificationGateway.initialize();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(MichizureApp(bootstrapState: bootstrapState));
}
