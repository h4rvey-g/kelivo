enum ImageContextInheritanceMode { summary, fullConversation }

extension ImageContextInheritanceModeCodec on ImageContextInheritanceMode {
  String get storageValue => switch (this) {
    ImageContextInheritanceMode.summary => 'summary',
    ImageContextInheritanceMode.fullConversation => 'full_conversation',
  };

  static ImageContextInheritanceMode fromStorage(Object? raw) {
    return raw == 'full_conversation'
        ? ImageContextInheritanceMode.fullConversation
        : ImageContextInheritanceMode.summary;
  }
}

/// Branch-local context snapshot for one image-generation turn.
///
/// Every assistant image revision owns a complete snapshot. A later image turn
/// can therefore resume after an app restart without consulting mutable
/// conversation-level state, while selecting another message revision selects
/// the matching image context automatically.
class ImageGenerationContext {
  static const String extrasKey = 'image_generation.context.v1';
  static const int schemaVersion = 1;

  const ImageGenerationContext({
    required this.stageId,
    required this.inheritanceMode,
    required this.inheritedContext,
    required this.modificationLog,
    this.summaryFallback = false,
    this.textOnlyFallback = false,
    this.inputImageUri,
  });

  final String stageId;
  final ImageContextInheritanceMode inheritanceMode;
  final String inheritedContext;
  final List<String> modificationLog;
  final bool summaryFallback;
  final bool textOnlyFallback;
  final String? inputImageUri;

  String get currentRequest =>
      modificationLog.isEmpty ? '' : modificationLog.last;

  String buildImagePrompt() {
    final buffer = StringBuffer()
      ..writeln('Use the following initial creative context:')
      ..writeln('<initial_creative_context>')
      ..writeln(inheritedContext)
      ..writeln('</initial_creative_context>');
    if (modificationLog.length > 1) {
      buffer
        ..writeln()
        ..writeln(
          'Apply these later changes in order. Newer changes override older ones:',
        )
        ..writeln('<previous_changes>');
      for (var i = 0; i < modificationLog.length - 1; i++) {
        buffer.writeln('${i + 1}. ${modificationLog[i]}');
      }
      buffer.writeln('</previous_changes>');
    }
    buffer
      ..writeln()
      ..writeln('The current request has highest priority:')
      ..writeln('<current_request>')
      ..writeln(currentRequest)
      ..writeln('</current_request>');
    return buffer.toString().trim();
  }

  String buildImageDescription() {
    final buffer = StringBuffer('[Generated image] ')
      ..write(inheritedContext.trim());
    if (modificationLog.isNotEmpty) {
      buffer
        ..write('\nApplied requests: ')
        ..write(modificationLog.join(' -> '));
    }
    return buffer.toString();
  }

  ImageGenerationContext copyWith({
    String? inheritedContext,
    List<String>? modificationLog,
    bool? summaryFallback,
    bool? textOnlyFallback,
    String? inputImageUri,
    bool clearInputImageUri = false,
  }) {
    return ImageGenerationContext(
      stageId: stageId,
      inheritanceMode: inheritanceMode,
      inheritedContext: inheritedContext ?? this.inheritedContext,
      modificationLog: modificationLog ?? this.modificationLog,
      summaryFallback: summaryFallback ?? this.summaryFallback,
      textOnlyFallback: textOnlyFallback ?? this.textOnlyFallback,
      inputImageUri: clearInputImageUri
          ? null
          : (inputImageUri ?? this.inputImageUri),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': schemaVersion,
      'stageId': stageId,
      'inheritanceMode': inheritanceMode.storageValue,
      'inheritedContext': inheritedContext,
      'modificationLog': modificationLog,
      'summaryFallback': summaryFallback,
      'textOnlyFallback': textOnlyFallback,
      if (inputImageUri != null) 'inputImageUri': inputImageUri,
    };
  }

  Map<String, dynamic> mergeIntoExtras([
    Map<String, dynamic> extras = const <String, dynamic>{},
  ]) {
    return <String, dynamic>{...extras, extrasKey: toJson()};
  }

  static ImageGenerationContext? fromExtras(Map<String, dynamic> extras) {
    final raw = extras[extrasKey];
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    if ((map['version'] as num?)?.toInt() != schemaVersion) return null;
    final stageId = (map['stageId'] ?? '').toString().trim();
    final inheritedContext = (map['inheritedContext'] ?? '').toString().trim();
    final rawLog = map['modificationLog'];
    if (stageId.isEmpty || inheritedContext.isEmpty || rawLog is! List) {
      return null;
    }
    final modificationLog = <String>[
      for (final item in rawLog)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
    return ImageGenerationContext(
      stageId: stageId,
      inheritanceMode: ImageContextInheritanceModeCodec.fromStorage(
        map['inheritanceMode'],
      ),
      inheritedContext: inheritedContext,
      modificationLog: List<String>.unmodifiable(modificationLog),
      summaryFallback: map['summaryFallback'] == true,
      textOnlyFallback: map['textOnlyFallback'] == true,
      inputImageUri: switch ((map['inputImageUri'] ?? '').toString().trim()) {
        final value when value.isNotEmpty => value,
        _ => null,
      },
    );
  }
}
