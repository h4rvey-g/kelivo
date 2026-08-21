import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update/update_installer.dart';

const String _updateRepository = 'h4rvey-g/kelivo';
const String _releasesApiUrl =
    'https://api.github.com/repos/$_updateRepository/releases?per_page=20';
const String _latestReleasePageUrl =
    'https://github.com/$_updateRepository/releases/latest';

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;
  final Map<String, UpdateArtifact> artifacts;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
    this.artifacts = const {},
  });

  String? bestDownloadUrl() {
    final target = detectUpdateTarget();
    if (target == UpdateTarget.ios) {
      return downloads['ios'] ??
          downloads['iosAppStore'] ??
          downloads['universal'];
    }
    if (target.isAndroid) {
      if (target == UpdateTarget.androidArm64) {
        return downloads['androidArm64'] ??
            downloads['android'] ??
            downloads['universal'];
      }
      if (target == UpdateTarget.androidArm) {
        return downloads['androidArm'] ??
            downloads['android'] ??
            downloads['universal'];
      }
      return downloads['androidX64'] ??
          downloads['android'] ??
          downloads['universal'];
    }
    if (target == UpdateTarget.macos) {
      return downloads['macos'] ??
          downloads['mac'] ??
          downloads['darwin'] ??
          downloads['universal'];
    }
    if (target == UpdateTarget.windows) {
      return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    }
    if (target.isLinux) {
      if (target == UpdateTarget.linuxArm64) {
        return downloads['linuxArm64'] ??
            downloads['linuxX64'] ??
            downloads['universal'];
      }
      return downloads['linuxX64'] ??
          downloads['linuxArm64'] ??
          downloads['universal'];
    }
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  UpdateArtifact? bestInstallableArtifact() =>
      bestInstallableArtifactFor(detectUpdateTarget());

  UpdateArtifact? bestInstallableArtifactFor(UpdateTarget target) {
    UpdateArtifact? firstAvailable(List<String> keys) {
      for (final key in keys) {
        final artifact = artifacts[key];
        if (artifact != null && isInstallableUpdateArtifact(artifact, target)) {
          return artifact;
        }
      }
      return null;
    }

    return switch (target) {
      UpdateTarget.androidArm64 => firstAvailable(['androidArm64', 'android']),
      UpdateTarget.androidArm => firstAvailable(['androidArm', 'android']),
      UpdateTarget.androidX64 => firstAvailable(['androidX64', 'android']),
      UpdateTarget.macos => firstAvailable(['macos', 'mac', 'darwin']),
      UpdateTarget.windows => firstAvailable(['windows', 'win']),
      UpdateTarget.linuxArm64 => firstAvailable(['linuxArm64']),
      UpdateTarget.linuxX64 => firstAvailable(['linuxX64']),
      UpdateTarget.ios || UpdateTarget.unsupported => null,
    };
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        released = DateTime.parse(releasedRaw);
      } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }

  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> json) {
    final assets = <UpdateArtifact>[];
    for (final rawAsset in (json['assets'] as List?) ?? const []) {
      if (rawAsset is! Map) continue;
      final name = rawAsset['name']?.toString() ?? '';
      final url = rawAsset['browser_download_url']?.toString() ?? '';
      final uri = Uri.tryParse(url);
      if (name.isNotEmpty && uri != null && uri.hasScheme) {
        final parsedSize = int.tryParse(rawAsset['size']?.toString() ?? '');
        assets.add(
          UpdateArtifact(
            name: name,
            uri: uri,
            sizeBytes: parsedSize != null && parsedSize > 0 ? parsedSize : null,
          ),
        );
      }
    }

    final releasePage = json['html_url']?.toString();
    final downloads = <String, String>{
      'universal': releasePage?.isNotEmpty == true
          ? releasePage!
          : _latestReleasePageUrl,
    };
    final artifactsByPlatform = <String, UpdateArtifact>{};

    void addAsset(String key, List<bool Function(String)> matchers) {
      final artifact = _findAsset(assets, matchers);
      if (artifact == null) return;
      downloads[key] = artifact.uri.toString();
      artifactsByPlatform[key] = artifact;
    }

    addAsset('androidArm64', [(name) => name.endsWith('_arm64-v8a.apk')]);
    addAsset('androidArm', [(name) => name.endsWith('_armeabi-v7a.apk')]);
    addAsset('androidX64', [(name) => name.endsWith('_x86_64.apk')]);
    addAsset('android', [
      (name) => name.endsWith('.apk') && !_isAndroidAbiAsset(name),
    ]);
    addAsset('ios', [(name) => name.endsWith('.ipa')]);
    addAsset('macos', [
      (name) => name.endsWith('.dmg'),
      (name) => name.endsWith('.pkg'),
    ]);
    addAsset('windows', [
      (name) => name.contains('windows') && name.endsWith('_setup.exe'),
      (name) => name.contains('windows') && name.endsWith('.exe'),
      (name) => name.contains('windows') && name.endsWith('.msix'),
      (name) => name.contains('windows') && name.endsWith('.zip'),
    ]);
    addAsset('linuxArm64', [
      (name) => _isArm64LinuxAsset(name) && name.endsWith('.appimage'),
      (name) => _isArm64LinuxAsset(name) && name.endsWith('.deb'),
      (name) => _isArm64LinuxAsset(name) && name.endsWith('.rpm'),
      (name) => _isArm64LinuxAsset(name) && name.endsWith('.tar.gz'),
    ]);
    addAsset('linuxX64', [
      (name) => _isX64LinuxAsset(name) && name.endsWith('.appimage'),
      (name) => _isX64LinuxAsset(name) && name.endsWith('.deb'),
      (name) => _isX64LinuxAsset(name) && name.endsWith('.rpm'),
      (name) => _isX64LinuxAsset(name) && name.endsWith('.tar.gz'),
    ]);

    final publishedAt =
        json['published_at']?.toString() ?? json['created_at']?.toString();

    return UpdateInfo(
      app: 'Kelivo',
      version: _versionFromReleaseTag(json['tag_name']?.toString() ?? ''),
      releasedAt: publishedAt == null ? null : DateTime.tryParse(publishedAt),
      notes: json['body']?.toString(),
      downloads: downloads,
      artifacts: artifactsByPlatform,
    );
  }

  factory UpdateInfo.fromGitHubReleases(List<dynamic> releases) {
    for (final release in releases) {
      if (release is! Map ||
          release['draft'] == true ||
          release['prerelease'] == true) {
        continue;
      }
      return UpdateInfo.fromGitHubRelease(
        release.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    throw const FormatException('No published GitHub release found');
  }
}

UpdateArtifact? _findAsset(
  List<UpdateArtifact> assets,
  List<bool Function(String)> matchers,
) {
  for (final matches in matchers) {
    for (final asset in assets) {
      if (matches(asset.name.toLowerCase())) return asset;
    }
  }
  return null;
}

bool _isArm64LinuxAsset(String name) {
  return name.contains('linux') &&
      (name.contains('arm64') || name.contains('aarch64'));
}

bool _isAndroidAbiAsset(String name) {
  return name.contains('_arm64-v8a') ||
      name.contains('_armeabi-v7a') ||
      name.contains('_x86_64') ||
      name.contains('_x86.');
}

bool _isX64LinuxAsset(String name) {
  return name.contains('linux') &&
      !name.contains('arm64') &&
      !name.contains('aarch64');
}

String _versionFromReleaseTag(String tag) {
  final match = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(tag);
  return match?.group(1) ?? tag.replaceFirst(RegExp(r'^[vV]'), '');
}

enum UpdateInstallResult { opened, unavailable, busy, failed }

class UpdateProvider extends ChangeNotifier {
  UpdateProvider({
    UpdateInstallationService? installationService,
    @visibleForTesting UpdateInfo? initialAvailable,
    @visibleForTesting UpdateTarget Function()? targetResolver,
  }) : _installationService =
           installationService ?? createDefaultUpdateInstallationService(),
       _ownsInstallationService = installationService == null,
       _available = initialAvailable,
       _targetResolver = targetResolver ?? detectUpdateTarget;

  final UpdateInstallationService _installationService;
  final bool _ownsInstallationService;
  final UpdateTarget Function() _targetResolver;

  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;
  UpdateInstallProgress? _installProgress;
  UpdateInstallProgress? get installProgress => _installProgress;
  bool get installing => _installProgress != null;
  String? _installError;
  String? get installError => _installError;

  Future<UpdateInstallResult> downloadAndInstall() async {
    if (installing) return UpdateInstallResult.busy;
    final info = _available;
    final target = _targetResolver();
    final artifact = info?.bestInstallableArtifactFor(target);
    if (artifact == null) return UpdateInstallResult.unavailable;

    _installError = null;
    _installProgress = const UpdateInstallProgress(
      phase: UpdateInstallPhase.downloading,
      receivedBytes: 0,
      totalBytes: null,
    );
    notifyListeners();
    var result = UpdateInstallResult.failed;
    try {
      await _installationService.downloadAndInstall(
        artifact,
        target: target,
        expectedVersion: info!.version,
        onProgress: _setInstallProgress,
      );
      result = UpdateInstallResult.opened;
    } catch (error) {
      _installError = error.toString();
    } finally {
      _installProgress = null;
      notifyListeners();
    }
    return result;
  }

  void _setInstallProgress(UpdateInstallProgress progress) {
    final previous = _installProgress;
    if (previous?.phase == progress.phase &&
        previous?.percent == progress.percent) {
      return;
    }
    _installProgress = progress;
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      final url = Uri.parse(_releasesApiUrl);
      final resp = await http.get(
        url,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Kelivo-update-checker',
          'Cache-Control': 'no-cache',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! List) {
        throw const FormatException('GitHub releases response is not a list');
      }
      final info = UpdateInfo.fromGitHubReleases(decoded);
      if (info.version.isEmpty) {
        throw const FormatException('GitHub release is missing a version tag');
      }

      final pkg = await PackageInfo.fromPlatform();
      final currentVer = pkg.version; // e.g., 1.0.0

      // Compare by version only; ignore build numbers
      final hasNew = _isRemoteNewer(
        remoteVersion: info.version,
        currentVersion: currentVer,
      );
      _available = hasNew ? info : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final parts = v.split('.');
      final nums = <int>[];
      for (int i = 0; i < 3; i++) {
        nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
      }
      return nums;
    }

    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }

  @override
  void dispose() {
    if (_ownsInstallationService) _installationService.dispose();
    super.dispose();
  }
}
