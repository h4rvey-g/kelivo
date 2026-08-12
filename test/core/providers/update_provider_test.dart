import 'package:Kelivo/core/providers/update_provider.dart';
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
}
