import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String _updateRepositoryOwner = 'h4rvey-g';
const String _updateRepositoryName = 'kelivo';

enum UpdateTarget {
  androidArm64,
  androidArm,
  androidX64,
  ios,
  macos,
  windows,
  linuxArm64,
  linuxX64,
  unsupported,
}

extension UpdateTargetPlatform on UpdateTarget {
  bool get isAndroid =>
      this == UpdateTarget.androidArm64 ||
      this == UpdateTarget.androidArm ||
      this == UpdateTarget.androidX64;

  bool get isLinux =>
      this == UpdateTarget.linuxArm64 || this == UpdateTarget.linuxX64;
}

UpdateTarget detectUpdateTarget() {
  if (Platform.isIOS) return UpdateTarget.ios;
  if (Platform.isAndroid) {
    return switch (Abi.current()) {
      Abi.androidArm64 => UpdateTarget.androidArm64,
      Abi.androidArm => UpdateTarget.androidArm,
      _ => UpdateTarget.androidX64,
    };
  }
  if (Platform.isMacOS) return UpdateTarget.macos;
  if (Platform.isWindows) return UpdateTarget.windows;
  if (Platform.isLinux) {
    return Abi.current() == Abi.linuxArm64
        ? UpdateTarget.linuxArm64
        : UpdateTarget.linuxX64;
  }
  return UpdateTarget.unsupported;
}

@immutable
final class UpdateArtifact {
  const UpdateArtifact({required this.name, required this.uri, this.sizeBytes});

  final String name;
  final Uri uri;
  final int? sizeBytes;
}

bool isInstallableUpdateArtifact(UpdateArtifact artifact, UpdateTarget target) {
  final name = artifact.name.toLowerCase();
  return switch (target) {
    UpdateTarget.androidArm64 ||
    UpdateTarget.androidArm ||
    UpdateTarget.androidX64 => name.endsWith('.apk'),
    UpdateTarget.macos => name.endsWith('.dmg') || name.endsWith('.pkg'),
    UpdateTarget.windows =>
      name.endsWith('.exe') ||
          name.endsWith('.msix') ||
          name.endsWith('.msixbundle'),
    UpdateTarget.linuxArm64 || UpdateTarget.linuxX64 =>
      name.endsWith('.appimage') ||
          name.endsWith('.deb') ||
          name.endsWith('.rpm'),
    UpdateTarget.ios || UpdateTarget.unsupported => false,
  };
}

enum UpdateInstallPhase { downloading, requestingPermission, openingInstaller }

@immutable
final class UpdateInstallProgress {
  const UpdateInstallProgress({
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final UpdateInstallPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  int? get percent {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (receivedBytes <= 0) return 0;
    if (receivedBytes >= total) return 100;
    return (receivedBytes * 100) ~/ total;
  }
}

typedef UpdateInstallProgressCallback =
    void Function(UpdateInstallProgress progress);

abstract interface class UpdateInstallationService {
  Future<void> downloadAndInstall(
    UpdateArtifact artifact, {
    required UpdateTarget target,
    required String expectedVersion,
    UpdateInstallProgressCallback? onProgress,
  });

  void dispose();
}

typedef UpdateInstallerOpener = Future<bool> Function(String path);
typedef UpdateInstallPermissionRequester = Future<bool> Function();
typedef UpdateExecutablePreparer = Future<void> Function(String path);

UpdateInstallationService createDefaultUpdateInstallationService() {
  if (Platform.isMacOS) return MacOSSparkleUpdateInstaller();
  return InternalUpdateInstaller();
}

final class MacOSSparkleUpdateInstaller implements UpdateInstallationService {
  MacOSSparkleUpdateInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String _channelName = 'com.psyche.kelivo/sparkle_update';

  final MethodChannel _channel;
  UpdateInstallProgressCallback? _onProgress;
  bool _disposed = false;

  @override
  Future<void> downloadAndInstall(
    UpdateArtifact artifact, {
    required UpdateTarget target,
    required String expectedVersion,
    UpdateInstallProgressCallback? onProgress,
  }) async {
    if (target != UpdateTarget.macos ||
        !isInstallableUpdateArtifact(artifact, target)) {
      throw const UpdateInstallerException(
        'The selected release asset is not a macOS update.',
      );
    }
    if (!_isTrustedReleaseArtifact(artifact)) {
      throw const UpdateInstallerException(
        'The selected update is not hosted by the Kelivo release repository.',
      );
    }
    if (_disposed) {
      throw const UpdateInstallerException(
        'The macOS update service is unavailable.',
      );
    }

    _onProgress = onProgress;
    try {
      await _channel.invokeMethod<void>('installAvailableUpdate', {
        'expectedVersion': expectedVersion,
      });
    } on PlatformException catch (error) {
      throw UpdateInstallerException(
        error.message ?? 'The macOS update could not be installed.',
      );
    } finally {
      _onProgress = null;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'progress') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;

    final phase = switch (arguments['phase']) {
      'downloading' => UpdateInstallPhase.downloading,
      'preparing' => UpdateInstallPhase.requestingPermission,
      'installing' => UpdateInstallPhase.openingInstaller,
      _ => null,
    };
    if (phase == null) return;
    _onProgress?.call(
      UpdateInstallProgress(
        phase: phase,
        receivedBytes: (arguments['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (arguments['totalBytes'] as num?)?.toInt(),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _onProgress = null;
    _channel.setMethodCallHandler(null);
  }
}

final class InternalUpdateInstaller implements UpdateInstallationService {
  InternalUpdateInstaller({
    http.Client? httpClient,
    Directory? cacheRoot,
    UpdateInstallerOpener? openInstaller,
    UpdateInstallPermissionRequester? requestInstallPermission,
    UpdateExecutablePreparer? prepareExecutable,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _injectedCacheRoot = cacheRoot,
       _openInstaller = openInstaller ?? _defaultOpenInstaller,
       _requestInstallPermission =
           requestInstallPermission ?? _defaultRequestInstallPermission,
       _prepareExecutable = prepareExecutable ?? _defaultPrepareExecutable;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Directory? _injectedCacheRoot;
  final UpdateInstallerOpener _openInstaller;
  final UpdateInstallPermissionRequester _requestInstallPermission;
  final UpdateExecutablePreparer _prepareExecutable;

  @override
  Future<void> downloadAndInstall(
    UpdateArtifact artifact, {
    required UpdateTarget target,
    required String expectedVersion,
    UpdateInstallProgressCallback? onProgress,
  }) async {
    if (!isInstallableUpdateArtifact(artifact, target)) {
      throw const UpdateInstallerException(
        'The selected release asset is not an installer for this platform.',
      );
    }
    if (!_isTrustedReleaseArtifact(artifact)) {
      throw const UpdateInstallerException(
        'The selected installer is not hosted by the Kelivo release repository.',
      );
    }

    final fileName = _safeInstallerFileName(artifact.name);
    final cacheRoot = await _resolveCacheRoot();
    await cacheRoot.create(recursive: true);
    final installer = File(p.join(cacheRoot.path, fileName));
    final downloadedBytes = await _ensureDownloaded(
      artifact,
      installer,
      onProgress,
    );
    final totalBytes = artifact.sizeBytes ?? downloadedBytes;

    if (target.isAndroid) {
      onProgress?.call(
        UpdateInstallProgress(
          phase: UpdateInstallPhase.requestingPermission,
          receivedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ),
      );
      if (!await _requestInstallPermission()) {
        throw const UpdateInstallPermissionDeniedException();
      }
    }

    if (target.isLinux && fileName.toLowerCase().endsWith('.appimage')) {
      await _prepareExecutable(installer.path);
    }

    onProgress?.call(
      UpdateInstallProgress(
        phase: UpdateInstallPhase.openingInstaller,
        receivedBytes: downloadedBytes,
        totalBytes: totalBytes,
      ),
    );
    if (!await _openInstaller(installer.path)) {
      throw const UpdateInstallerException(
        'The operating system could not open the downloaded installer.',
      );
    }
  }

  Future<Directory> _resolveCacheRoot() async {
    final injected = _injectedCacheRoot;
    if (injected != null) return injected;
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, 'kelivo_updates'));
  }

  Future<int> _ensureDownloaded(
    UpdateArtifact artifact,
    File installer,
    UpdateInstallProgressCallback? onProgress,
  ) async {
    final expectedAssetBytes = _positiveBytes(artifact.sizeBytes);
    if (expectedAssetBytes != null && await installer.exists()) {
      final existingBytes = await installer.length();
      if (existingBytes == expectedAssetBytes) {
        onProgress?.call(
          UpdateInstallProgress(
            phase: UpdateInstallPhase.downloading,
            receivedBytes: existingBytes,
            totalBytes: expectedAssetBytes,
          ),
        );
        return existingBytes;
      }
      await installer.delete();
    }

    final partFile = File('${installer.path}.part');
    if (await partFile.exists()) await partFile.delete();
    try {
      final request = http.Request('GET', artifact.uri)
        ..headers.addAll(const {
          'Accept': 'application/octet-stream',
          'User-Agent': 'Kelivo-internal-updater',
          'Cache-Control': 'no-cache',
        });
      final response = await _httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw UpdateInstallerException(
          'Installer download failed with HTTP ${response.statusCode}.',
        );
      }

      final responseBytes = _positiveBytes(response.contentLength);
      if (expectedAssetBytes != null &&
          responseBytes != null &&
          expectedAssetBytes != responseBytes) {
        await response.stream.drain<void>();
        throw const UpdateInstallerException(
          'The installer size does not match the release metadata.',
        );
      }
      final expectedBytes = expectedAssetBytes ?? responseBytes;
      var receivedBytes = 0;
      onProgress?.call(
        UpdateInstallProgress(
          phase: UpdateInstallPhase.downloading,
          receivedBytes: 0,
          totalBytes: expectedBytes,
        ),
      );

      final sink = partFile.openWrite(mode: FileMode.writeOnly);
      final iterator = StreamIterator<List<int>>(response.stream);
      try {
        while (await iterator.moveNext()) {
          final chunk = iterator.current;
          receivedBytes += chunk.length;
          if (expectedBytes != null && receivedBytes > expectedBytes) {
            throw const UpdateInstallerException(
              'The installer download exceeded its expected size.',
            );
          }
          sink.add(chunk);
          onProgress?.call(
            UpdateInstallProgress(
              phase: UpdateInstallPhase.downloading,
              receivedBytes: receivedBytes,
              totalBytes: expectedBytes,
            ),
          );
        }
        if (receivedBytes <= 0) {
          throw const UpdateInstallerException(
            'The installer download was empty.',
          );
        }
        if (expectedBytes != null && receivedBytes != expectedBytes) {
          throw const UpdateInstallerException(
            'The installer download ended before completion.',
          );
        }
        await sink.flush();
      } finally {
        await iterator.cancel();
        await sink.close();
      }

      if (await installer.exists()) await installer.delete();
      await partFile.rename(installer.path);
      return receivedBytes;
    } catch (_) {
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  static Future<bool> _defaultOpenInstaller(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  static Future<bool> _defaultRequestInstallPermission() async {
    final current = await Permission.requestInstallPackages.status;
    if (current.isGranted) return true;
    final requested = await Permission.requestInstallPackages.request();
    return requested.isGranted;
  }

  static Future<void> _defaultPrepareExecutable(String path) async {
    final result = await Process.run('chmod', ['755', path]);
    if (result.exitCode != 0) {
      throw const UpdateInstallerException(
        'The downloaded AppImage could not be made executable.',
      );
    }
  }
}

final class UpdateInstallerException implements Exception {
  const UpdateInstallerException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class UpdateInstallPermissionDeniedException
    extends UpdateInstallerException {
  const UpdateInstallPermissionDeniedException()
    : super('Permission to install apps from Kelivo was not granted.');
}

int? _positiveBytes(int? value) => value != null && value > 0 ? value : null;

bool _isTrustedReleaseArtifact(UpdateArtifact artifact) {
  final uri = artifact.uri;
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != 'github.com') {
    return false;
  }
  final segments = uri.pathSegments;
  return segments.length >= 5 &&
      !segments.any((segment) => segment == '.' || segment == '..') &&
      segments[0].toLowerCase() == _updateRepositoryOwner &&
      segments[1].toLowerCase() == _updateRepositoryName &&
      segments[2].toLowerCase() == 'releases' &&
      segments[3].toLowerCase() == 'download' &&
      segments.last == artifact.name;
}

String _safeInstallerFileName(String rawName) {
  final baseName = p.basename(rawName.trim());
  if (baseName.isEmpty || baseName == '.' || baseName == '..') {
    throw const UpdateInstallerException('The installer file name is invalid.');
  }
  final sanitized = baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    throw const UpdateInstallerException('The installer file name is invalid.');
  }
  return sanitized;
}
