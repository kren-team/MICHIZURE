import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/error/bootstrap_exception.dart';
import '../core/platform/runtime_platform.dart';

const String demoFirebaseProjectId = 'demo-michizure';
const int authEmulatorPort = 9099;
const int firestoreEmulatorPort = 8080;

enum AppEnvironment { firebaseEmulator, live }

@immutable
final class BootstrapState {
  const BootstrapState({
    required this.environment,
    required this.projectId,
    required this.startedAt,
  });

  final AppEnvironment environment;
  final String projectId;
  final DateTime startedAt;
}

@immutable
final class FirebaseBootstrapSettings {
  const FirebaseBootstrapSettings({
    required this.environment,
    required this.options,
    this.emulatorHost,
  });

  final AppEnvironment environment;
  final FirebaseOptions options;
  final String? emulatorHost;

  static FirebaseBootstrapSettings resolve({
    required bool isDebug,
    required RuntimePlatform platform,
    bool? useFirebaseEmulators,
    FirebaseOptions? liveOptions,
    String emulatorHost = '10.0.2.2',
  }) {
    if (platform != RuntimePlatform.android) {
      throw UnsupportedError('MICHIZURE supports Android only.');
    }

    if (useFirebaseEmulators ?? isDebug) {
      return FirebaseBootstrapSettings(
        environment: AppEnvironment.firebaseEmulator,
        options: demoFirebaseOptions,
        emulatorHost: emulatorHost,
      );
    }

    if (liveOptions == null) {
      throw const MissingLiveFirebaseConfiguration();
    }

    return FirebaseBootstrapSettings(
      environment: AppEnvironment.live,
      options: liveOptions,
    );
  }
}

const FirebaseOptions demoFirebaseOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:1234567890:android:demo-michizure',
  messagingSenderId: '1234567890',
  projectId: demoFirebaseProjectId,
);

FirebaseOptions? liveFirebaseOptionsFromDartDefines() {
  const apiKey = String.fromEnvironment('MICHIZURE_FIREBASE_API_KEY');
  const appId = String.fromEnvironment('MICHIZURE_FIREBASE_APP_ID');
  const messagingSenderId = String.fromEnvironment(
    'MICHIZURE_FIREBASE_MESSAGING_SENDER_ID',
  );
  const projectId = String.fromEnvironment('MICHIZURE_FIREBASE_PROJECT_ID');

  if ([
    apiKey,
    appId,
    messagingSenderId,
    projectId,
  ].any((value) => value.isEmpty)) {
    return null;
  }

  return const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}

abstract interface class FirebaseGateway {
  Future<void> initialize(FirebaseOptions options);

  Future<void> connectToEmulators({
    required String host,
    required int authPort,
    required int firestorePort,
  });
}

final class FlutterFireGateway implements FirebaseGateway {
  @override
  Future<void> initialize(FirebaseOptions options) async {
    await Firebase.initializeApp(options: options);
  }

  @override
  Future<void> connectToEmulators({
    required String host,
    required int authPort,
    required int firestorePort,
  }) async {
    await FirebaseAuth.instance.useAuthEmulator(host, authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  }
}

final class AppBootstrap {
  const AppBootstrap({required this.settings, required this.firebaseGateway});

  final FirebaseBootstrapSettings settings;
  final FirebaseGateway firebaseGateway;

  Future<BootstrapState> run() async {
    try {
      await firebaseGateway.initialize(settings.options);
      final emulatorHost = settings.emulatorHost;
      if (settings.environment == AppEnvironment.firebaseEmulator &&
          emulatorHost != null) {
        await firebaseGateway.connectToEmulators(
          host: emulatorHost,
          authPort: authEmulatorPort,
          firestorePort: firestoreEmulatorPort,
        );
      }
    } on BootstrapException {
      rethrow;
    } catch (error) {
      throw FirebaseBootstrapException(
        'Firebase initialization failed.',
        cause: error,
      );
    }

    return BootstrapState(
      environment: settings.environment,
      projectId: settings.options.projectId,
      startedAt: DateTime.now().toUtc(),
    );
  }
}

FirebaseBootstrapSettings currentFirebaseBootstrapSettings() {
  const useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: kDebugMode,
  );
  const emulatorHost = String.fromEnvironment(
    'MICHIZURE_FIREBASE_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  return FirebaseBootstrapSettings.resolve(
    isDebug: kDebugMode,
    platform: RuntimePlatform.android,
    useFirebaseEmulators: useFirebaseEmulators,
    liveOptions: liveFirebaseOptionsFromDartDefines(),
    emulatorHost: emulatorHost,
  );
}
