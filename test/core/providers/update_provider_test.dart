import 'dart:async';

import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/core/services/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateInfo.fromGitHubRelease', () {
    test('maps release metadata and preferred platform assets', () {
      final info = UpdateInfo.fromGitHubRelease({
        'tag_name': 'v1.2.3',
        'published_at': '2026-08-12T08:30:00Z',
        'body': 'Release notes',
        'html_url': 'https://github.com/h4rvey-g/kelivo/releases/tag/v1.2.3',
        'assets': [
          {
            'name': 'Kelivo_android_1.2.3_x86_64.apk',
            'browser_download_url': 'https://example.test/android-x64',
          },
          {
            'name': 'Kelivo_android_1.2.3_arm64-v8a.apk',
            'browser_download_url': 'https://example.test/android-arm64',
            'size': 12345,
          },
          {
            'name': 'Kelivo_ios_1.2.3.ipa',
            'browser_download_url': 'https://example.test/ios',
          },
          {
            'name': 'Kelivo_macos_1.2.3.dmg',
            'browser_download_url': 'https://example.test/macos',
          },
          {
            'name': 'Kelivo_windows_1.2.3.zip',
            'browser_download_url': 'https://example.test/windows-zip',
          },
          {
            'name': 'Kelivo_windows_1.2.3_setup.exe',
            'browser_download_url': 'https://example.test/windows-setup',
          },
          {
            'name': 'Kelivo_linux_1.2.3.AppImage',
            'browser_download_url': 'https://example.test/linux-x64',
          },
          {
            'name': 'Kelivo_linux_1.2.3_arm64.AppImage',
            'browser_download_url': 'https://example.test/linux-arm64',
          },
        ],
      });

      expect(info.app, 'Kelivo');
      expect(info.version, '1.2.3');
      expect(info.releasedAt, DateTime.utc(2026, 8, 12, 8, 30));
      expect(info.notes, 'Release notes');
      expect(
        info.downloads['androidArm64'],
        'https://example.test/android-arm64',
      );
      expect(info.downloads['androidX64'], 'https://example.test/android-x64');
      expect(info.downloads['ios'], 'https://example.test/ios');
      expect(info.downloads['macos'], 'https://example.test/macos');
      expect(info.downloads['windows'], 'https://example.test/windows-setup');
      expect(info.downloads['linuxX64'], 'https://example.test/linux-x64');
      expect(info.downloads['linuxArm64'], 'https://example.test/linux-arm64');
      expect(
        info.downloads['universal'],
        'https://github.com/h4rvey-g/kelivo/releases/tag/v1.2.3',
      );
      expect(info.artifacts['androidArm64']?.name, contains('arm64-v8a.apk'));
      expect(info.artifacts['androidArm64']?.sizeBytes, 12345);
      expect(
        info
            .bestInstallableArtifactFor(UpdateTarget.androidArm64)
            ?.uri
            .toString(),
        'https://example.test/android-arm64',
      );
      expect(
        info.bestInstallableArtifactFor(UpdateTarget.windows)?.uri.toString(),
        'https://example.test/windows-setup',
      );
      expect(
        info
            .bestInstallableArtifactFor(UpdateTarget.linuxArm64)
            ?.uri
            .toString(),
        'https://example.test/linux-arm64',
      );
      expect(info.bestInstallableArtifactFor(UpdateTarget.ios), isNull);
    });

    test('keeps archive-only releases on the external download path', () {
      final info = UpdateInfo.fromGitHubRelease({
        'tag_name': 'v1.2.3',
        'assets': [
          {
            'name': 'Kelivo_windows_1.2.3.zip',
            'browser_download_url': 'https://example.test/windows-zip',
          },
          {
            'name': 'Kelivo_linux_1.2.3.tar.gz',
            'browser_download_url': 'https://example.test/linux-tarball',
          },
        ],
      });

      expect(info.downloads['windows'], 'https://example.test/windows-zip');
      expect(info.bestInstallableArtifactFor(UpdateTarget.windows), isNull);
      expect(info.bestInstallableArtifactFor(UpdateTarget.linuxX64), isNull);
    });

    test('falls back to the repository release page without assets', () {
      final info = UpdateInfo.fromGitHubRelease({
        'tag_name': 'release-2.4',
        'created_at': '2026-08-12T08:30:00Z',
        'assets': const [],
      });

      expect(info.version, '2.4');
      expect(info.downloads, {
        'universal': 'https://github.com/h4rvey-g/kelivo/releases/latest',
      });
    });

    test('selects a prerelease when it is the newest non-draft release', () {
      final info = UpdateInfo.fromGitHubReleases([
        {'tag_name': 'v3.0.0-draft', 'draft': true},
        {
          'tag_name': 'v2.0.0-beta.1',
          'draft': false,
          'prerelease': true,
          'html_url':
              'https://github.com/h4rvey-g/kelivo/releases/tag/v2.0.0-beta.1',
        },
        {'tag_name': 'v1.9.0', 'draft': false, 'prerelease': false},
      ]);

      expect(info.version, '2.0.0');
      expect(
        info.downloads['universal'],
        'https://github.com/h4rvey-g/kelivo/releases/tag/v2.0.0-beta.1',
      );
    });

    test('rejects an empty release list', () {
      expect(
        () => UpdateInfo.fromGitHubReleases(const []),
        throwsFormatException,
      );
    });
  });

  group('UpdateProvider internal installation', () {
    late UpdateArtifact artifact;
    late UpdateInfo info;

    setUp(() {
      artifact = UpdateArtifact(
        name: 'Kelivo_windows_1.2.3_setup.exe',
        uri: Uri.parse(
          'https://github.com/h4rvey-g/kelivo/releases/download/'
          'v1.2.3/Kelivo_windows_1.2.3_setup.exe',
        ),
        sizeBytes: 10,
      );
      info = UpdateInfo(
        app: 'Kelivo',
        version: '1.2.3',
        downloads: {'windows': artifact.uri.toString()},
        artifacts: {'windows': artifact},
      );
    });

    test('publishes progress and opens the selected installer', () async {
      final service = _FakeUpdateInstallationService((artifact, target, emit) {
        emit?.call(
          const UpdateInstallProgress(
            phase: UpdateInstallPhase.downloading,
            receivedBytes: 5,
            totalBytes: 10,
          ),
        );
        emit?.call(
          const UpdateInstallProgress(
            phase: UpdateInstallPhase.openingInstaller,
            receivedBytes: 10,
            totalBytes: 10,
          ),
        );
        return Future.value();
      });
      final provider = UpdateProvider(
        installationService: service,
        initialAvailable: info,
        targetResolver: () => UpdateTarget.windows,
      );
      addTearDown(provider.dispose);
      final observed = <UpdateInstallProgress?>[];
      provider.addListener(() => observed.add(provider.installProgress));

      final result = await provider.downloadAndInstall();

      expect(result, UpdateInstallResult.opened);
      expect(service.receivedArtifact, same(artifact));
      expect(service.receivedTarget, UpdateTarget.windows);
      expect(
        observed.whereType<UpdateInstallProgress>().map((p) => p.phase),
        containsAllInOrder([
          UpdateInstallPhase.downloading,
          UpdateInstallPhase.openingInstaller,
        ]),
      );
      expect(provider.installing, isFalse);
      expect(provider.installError, isNull);
    });

    test('rejects a second install while one is active', () async {
      final release = Completer<void>();
      final service = _FakeUpdateInstallationService(
        (_, _, _) => release.future,
      );
      final provider = UpdateProvider(
        installationService: service,
        initialAvailable: info,
        targetResolver: () => UpdateTarget.windows,
      );
      addTearDown(provider.dispose);

      final first = provider.downloadAndInstall();
      expect(provider.installing, isTrue);
      expect(await provider.downloadAndInstall(), UpdateInstallResult.busy);
      release.complete();

      expect(await first, UpdateInstallResult.opened);
      expect(provider.installing, isFalse);
    });

    test('retains an installation error for the UI', () async {
      final service = _FakeUpdateInstallationService((_, _, _) async {
        throw const UpdateInstallerException('installer failed');
      });
      final provider = UpdateProvider(
        installationService: service,
        initialAvailable: info,
        targetResolver: () => UpdateTarget.windows,
      );
      addTearDown(provider.dispose);

      final result = await provider.downloadAndInstall();

      expect(result, UpdateInstallResult.failed);
      expect(provider.installError, 'installer failed');
      expect(provider.installing, isFalse);
    });
  });
}

typedef _FakeInstallAction =
    Future<void> Function(
      UpdateArtifact artifact,
      UpdateTarget target,
      UpdateInstallProgressCallback? onProgress,
    );

final class _FakeUpdateInstallationService
    implements UpdateInstallationService {
  _FakeUpdateInstallationService(this.action);

  final _FakeInstallAction action;
  UpdateArtifact? receivedArtifact;
  UpdateTarget? receivedTarget;

  @override
  Future<void> downloadAndOpen(
    UpdateArtifact artifact, {
    required UpdateTarget target,
    UpdateInstallProgressCallback? onProgress,
  }) {
    receivedArtifact = artifact;
    receivedTarget = target;
    return action(artifact, target, onProgress);
  }

  @override
  void dispose() {}
}
