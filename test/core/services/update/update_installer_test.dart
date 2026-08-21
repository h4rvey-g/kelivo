import 'dart:io';

import 'package:Kelivo/core/services/update/update_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacOSSparkleUpdateInstaller', () {
    const channel = MethodChannel('kelivo.test/sparkle_update');

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('starts Sparkle with the expected release version', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return null;
          });
      final installer = MacOSSparkleUpdateInstaller(channel: channel);
      addTearDown(installer.dispose);

      await installer.downloadAndInstall(
        _artifact(name: 'Kelivo_macos_1.2.3.dmg'),
        target: UpdateTarget.macos,
        expectedVersion: '1.2.3',
      );

      expect(receivedCall?.method, 'installAvailableUpdate');
      expect(receivedCall?.arguments, {'expectedVersion': '1.2.3'});
    });

    test('surfaces native Sparkle failures without platform noise', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'update_failed',
              message: 'signature rejected',
            );
          });
      final installer = MacOSSparkleUpdateInstaller(channel: channel);
      addTearDown(installer.dispose);

      await expectLater(
        installer.downloadAndInstall(
          _artifact(name: 'Kelivo_macos_1.2.3.dmg'),
          target: UpdateTarget.macos,
          expectedVersion: '1.2.3',
        ),
        throwsA(
          isA<UpdateInstallerException>().having(
            (error) => error.message,
            'message',
            'signature rejected',
          ),
        ),
      );
    });
  });

  group('InternalUpdateInstaller', () {
    late Directory cacheRoot;

    setUp(() async {
      cacheRoot = await Directory.systemTemp.createTemp(
        'kelivo_update_installer_test_',
      );
    });

    tearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    test('streams to cache and opens only the completed installer', () async {
      final payload = List<int>.generate(17, (index) => index + 1);
      final chunks = [
        payload.sublist(0, 4),
        payload.sublist(4, 11),
        payload.sublist(11),
      ];
      final client = _StreamingClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(chunks),
          HttpStatus.ok,
          contentLength: payload.length,
        ),
      );
      String? openedPath;
      final installer = InternalUpdateInstaller(
        httpClient: client,
        cacheRoot: cacheRoot,
        openInstaller: (path) async {
          openedPath = path;
          expect(await File(path).readAsBytes(), payload);
          expect(await File('$path.part').exists(), isFalse);
          return true;
        },
      );
      addTearDown(installer.dispose);
      final progress = <UpdateInstallProgress>[];

      await installer.downloadAndInstall(
        _artifact(
          name: 'Kelivo_windows_1.2.3_setup.exe',
          sizeBytes: payload.length,
        ),
        target: UpdateTarget.windows,
        expectedVersion: '1.2.3',
        onProgress: progress.add,
      );

      expect(
        openedPath,
        p.join(cacheRoot.path, 'Kelivo_windows_1.2.3_setup.exe'),
      );
      final downloadEvents = progress
          .where((event) => event.phase == UpdateInstallPhase.downloading)
          .toList();
      expect(downloadEvents.map((event) => event.receivedBytes), [
        0,
        4,
        11,
        17,
      ]);
      expect(downloadEvents.last.percent, 100);
      expect(progress.last.phase, UpdateInstallPhase.openingInstaller);
    });

    test('removes a partial file when the response ends early', () async {
      final payload = [1, 2, 3, 4];
      var opened = false;
      final installer = InternalUpdateInstaller(
        httpClient: _StreamingClient(
          (_) async => http.StreamedResponse(
            Stream<List<int>>.value(payload),
            HttpStatus.ok,
            contentLength: payload.length + 2,
          ),
        ),
        cacheRoot: cacheRoot,
        openInstaller: (_) async {
          opened = true;
          return true;
        },
      );
      addTearDown(installer.dispose);

      await expectLater(
        installer.downloadAndInstall(
          _artifact(name: 'Kelivo_macos_1.2.3.dmg'),
          target: UpdateTarget.macos,
          expectedVersion: '1.2.3',
        ),
        throwsA(isA<UpdateInstallerException>()),
      );

      expect(opened, isFalse);
      expect(await cacheRoot.list().toList(), isEmpty);
    });

    test(
      'keeps a verified APK for retry when install permission is denied',
      () async {
        final payload = [9, 8, 7, 6];
        var requestCount = 0;
        var permissionGranted = false;
        var openCount = 0;
        final installer = InternalUpdateInstaller(
          httpClient: _StreamingClient((_) async {
            requestCount++;
            return http.StreamedResponse(
              Stream<List<int>>.value(payload),
              HttpStatus.ok,
              contentLength: payload.length,
            );
          }),
          cacheRoot: cacheRoot,
          requestInstallPermission: () async => permissionGranted,
          openInstaller: (_) async {
            openCount++;
            return true;
          },
        );
        addTearDown(installer.dispose);
        final artifact = _artifact(
          name: 'Kelivo_android_1.2.3_arm64-v8a.apk',
          sizeBytes: payload.length,
        );

        await expectLater(
          installer.downloadAndInstall(
            artifact,
            target: UpdateTarget.androidArm64,
            expectedVersion: '1.2.3',
          ),
          throwsA(isA<UpdateInstallPermissionDeniedException>()),
        );

        expect(requestCount, 1);
        expect(openCount, 0);
        expect(
          await File(p.join(cacheRoot.path, artifact.name)).readAsBytes(),
          payload,
        );

        permissionGranted = true;
        await installer.downloadAndInstall(
          artifact,
          target: UpdateTarget.androidArm64,
          expectedVersion: '1.2.3',
        );

        expect(
          requestCount,
          1,
          reason: 'the verified cached APK should be reused',
        );
        expect(openCount, 1);
      },
    );

    test('rejects untrusted or mismatched installer URLs', () async {
      var requested = false;
      final installer = InternalUpdateInstaller(
        httpClient: _StreamingClient((_) async {
          requested = true;
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            HttpStatus.ok,
          );
        }),
        cacheRoot: cacheRoot,
      );
      addTearDown(installer.dispose);

      await expectLater(
        installer.downloadAndInstall(
          UpdateArtifact(
            name: 'Kelivo_windows_1.2.3_setup.exe',
            uri: Uri.parse('https://example.test/update.exe'),
          ),
          target: UpdateTarget.windows,
          expectedVersion: '1.2.3',
        ),
        throwsA(isA<UpdateInstallerException>()),
      );
      await expectLater(
        installer.downloadAndInstall(
          UpdateArtifact(
            name: 'Kelivo_windows_1.2.3_setup.exe',
            uri: Uri.parse(
              'https://github.com/h4rvey-g/kelivo/releases/download/'
              'v1.2.3/a_different_setup.exe',
            ),
          ),
          target: UpdateTarget.windows,
          expectedVersion: '1.2.3',
        ),
        throwsA(isA<UpdateInstallerException>()),
      );

      expect(requested, isFalse);
    });
  });
}

UpdateArtifact _artifact({required String name, int? sizeBytes}) {
  return UpdateArtifact(
    name: name,
    uri: Uri.parse(
      'https://github.com/h4rvey-g/kelivo/releases/download/v1.2.3/$name',
    ),
    sizeBytes: sizeBytes,
  );
}

typedef _SendHandler = Future<http.StreamedResponse> Function(http.BaseRequest);

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);

  final _SendHandler handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
