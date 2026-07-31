import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/core/error/bootstrap_exception.dart';
import 'package:michizure/core/platform/runtime_platform.dart';

void main() {
  group('FirebaseBootstrapSettings', () {
    test('debug build always targets demo-michizure', () {
      final settings = FirebaseBootstrapSettings.resolve(
        isDebug: true,
        platform: RuntimePlatform.android,
      );

      expect(settings.environment, AppEnvironment.firebaseEmulator);
      expect(settings.options.projectId, demoFirebaseProjectId);
      expect(settings.emulatorHost, '10.0.2.2');
    });

    test('profile build can explicitly use Firebase emulators', () {
      final settings = FirebaseBootstrapSettings.resolve(
        isDebug: false,
        useFirebaseEmulators: true,
        platform: RuntimePlatform.android,
      );

      expect(settings.environment, AppEnvironment.firebaseEmulator);
      expect(settings.options.projectId, demoFirebaseProjectId);
      expect(settings.emulatorHost, '10.0.2.2');
    });

    test('profile build without emulator or live configuration fails', () {
      expect(
        () => FirebaseBootstrapSettings.resolve(
          isDebug: false,
          useFirebaseEmulators: false,
          platform: RuntimePlatform.android,
        ),
        throwsA(isA<MissingLiveFirebaseConfiguration>()),
      );
    });

    test('explicit live options are used when emulators are disabled', () {
      const liveOptions = FirebaseOptions(
        apiKey: 'live-api-key',
        appId: 'live-app-id',
        messagingSenderId: 'live-sender-id',
        projectId: 'live-project-id',
      );

      final settings = FirebaseBootstrapSettings.resolve(
        isDebug: false,
        useFirebaseEmulators: false,
        platform: RuntimePlatform.android,
        liveOptions: liveOptions,
      );

      expect(settings.environment, AppEnvironment.live);
      expect(settings.options.projectId, 'live-project-id');
      expect(settings.emulatorHost, isNull);
    });
  });

  test('bootstrap initializes Firebase and connects both emulators', () async {
    final gateway = _FakeFirebaseGateway();
    final state = await AppBootstrap(
      settings: FirebaseBootstrapSettings.resolve(
        isDebug: true,
        platform: RuntimePlatform.android,
        emulatorHost: '127.0.0.1',
      ),
      firebaseGateway: gateway,
    ).run();

    expect(state.projectId, demoFirebaseProjectId);
    expect(state.environment, AppEnvironment.firebaseEmulator);
    expect(gateway.initializedProjectId, demoFirebaseProjectId);
    expect(gateway.emulatorHost, '127.0.0.1');
    expect(gateway.authPort, authEmulatorPort);
    expect(gateway.firestorePort, firestoreEmulatorPort);
  });
}

final class _FakeFirebaseGateway implements FirebaseGateway {
  String? initializedProjectId;
  String? emulatorHost;
  int? authPort;
  int? firestorePort;

  @override
  Future<void> initialize(FirebaseOptions options) async {
    initializedProjectId = options.projectId;
  }

  @override
  Future<void> connectToEmulators({
    required String host,
    required int authPort,
    required int firestorePort,
  }) async {
    emulatorHost = host;
    this.authPort = authPort;
    this.firestorePort = firestorePort;
  }
}
