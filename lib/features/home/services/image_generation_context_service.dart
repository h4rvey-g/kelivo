import '../../../core/models/chat_message.dart';
import '../../../core/models/compress_context_options.dart';
import '../../../core/models/image_generation_context.dart';
import '../../../core/models/message_part.dart';
import '../../../core/models/model_spec.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/providers/openai_images.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import 'message_builder_service.dart';

class PreparedImageGenerationContext {
  const PreparedImageGenerationContext({
    required this.context,
    required this.userMessageId,
  });

  final ImageGenerationContext context;
  final String userMessageId;
}

/// Builds an app-owned, branch-local context for stateless image endpoints.
class ImageGenerationContextService {
  const ImageGenerationContextService(this.messageBuilderService);

  final MessageBuilderService messageBuilderService;

  Future<PreparedImageGenerationContext?> prepare({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
    required String conversationId,
    ImageGenerationContext? seed,
  }) async {
    final targetConfig = settings.getProviderConfig(providerKey);
    if (!ChatApiService.supportsOpenAIImagesApiRouting(targetConfig, modelId)) {
      return null;
    }

    final selected = messageBuilderService.collapseVersions(
      messages,
      versionSelections,
    );
    if (selected.isEmpty) return null;

    final placeholder = selected.last.role == 'assistant'
        ? selected.last
        : null;
    final seeded = seed ?? placeholder?.imageGenerationContext;
    final userIndex = selected.lastIndexWhere(
      (message) => message.role == 'user',
    );
    if (userIndex < 0) return null;
    final currentUser = selected[userIndex];
    final request = currentUser.content.trim().isEmpty
        ? 'Create an image using the supplied visual reference and inherited context.'
        : currentUser.content.trim();
    final latestImageUri = _latestImageUri(selected.take(userIndex + 1));
    final supportsEdit = supportsOpenAIImageEdits(targetConfig, modelId);

    if (seeded != null) {
      return PreparedImageGenerationContext(
        context: seeded.copyWith(
          textOnlyFallback: latestImageUri != null && !supportsEdit,
          inputImageUri: latestImageUri,
          clearInputImageUri: latestImageUri == null,
        ),
        userMessageId: currentUser.id,
      );
    }

    final history = selected.take(userIndex).toList(growable: false);
    ChatMessage? previousAssistant;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].role == 'assistant') {
        previousAssistant = history[i];
        break;
      }
    }
    final previousContext = previousAssistant?.imageGenerationContext;
    if (previousContext != null) {
      return PreparedImageGenerationContext(
        context: previousContext.copyWith(
          modificationLog: <String>[
            ...previousContext.modificationLog,
            request,
          ],
          textOnlyFallback: latestImageUri != null && !supportsEdit,
          inputImageUri: latestImageUri,
          clearInputImageUri: latestImageUri == null,
        ),
        userMessageId: currentUser.id,
      );
    }

    final transcript = _visibleTranscript(history);
    final budget = _targetContextCharBudget(targetConfig, modelId);
    final fallbackContext = _truncateOldest(transcript, budget);
    var inheritedContext = fallbackContext.isEmpty
        ? 'No earlier visible conversation context.'
        : fallbackContext;
    var summaryFallback = false;
    final mode = settings.imageContextInheritanceMode;
    if (mode == ImageContextInheritanceMode.summary && transcript.isNotEmpty) {
      final summaryModel = _resolveSummaryModel(settings, history);
      if (summaryModel == null) {
        summaryFallback = true;
      } else {
        try {
          final summary = (await ChatApiService.generateText(
            conversationId: conversationId,
            config: settings.getProviderConfig(summaryModel.providerKey),
            modelId: summaryModel.modelId,
            prompt: _summaryPrompt(_truncateOldest(transcript, budget)),
            reasoning: settings.summaryGenerationReasoningFor(null),
            skipImageParsing: true,
          )).trim();
          if (summary.isEmpty) {
            summaryFallback = true;
          } else {
            inheritedContext = summary;
          }
        } catch (_) {
          summaryFallback = true;
        }
      }
    }

    return PreparedImageGenerationContext(
      context: ImageGenerationContext(
        stageId: currentUser.id,
        inheritanceMode: mode,
        inheritedContext: inheritedContext,
        modificationLog: <String>[request],
        summaryFallback: summaryFallback,
        textOnlyFallback: latestImageUri != null && !supportsEdit,
        inputImageUri: latestImageUri,
      ),
      userMessageId: currentUser.id,
    );
  }

  ({String providerKey, String modelId})? _resolveSummaryModel(
    SettingsProvider settings,
    List<ChatMessage> history,
  ) {
    final candidates = <({String? providerKey, String? modelId})>[
      (
        providerKey: settings.imageContextModelProvider,
        modelId: settings.imageContextModelId,
      ),
      for (var i = history.length - 1; i >= 0; i--)
        if (history[i].role == 'assistant')
          (providerKey: history[i].providerId, modelId: history[i].modelId),
      (
        providerKey: settings.currentModelProvider,
        modelId: settings.currentModelId,
      ),
    ];
    final seen = <String>{};
    for (final candidate in candidates) {
      final provider = candidate.providerKey;
      final model = candidate.modelId;
      if (provider == null || model == null) continue;
      if (!seen.add('$provider::$model')) continue;
      final config = settings.getProviderConfig(provider);
      if (ChatApiService.supportsOpenAIImagesApiRouting(config, model)) {
        continue;
      }
      if (!ModelSpecResolver.instance
          .spec(config, model)
          .output
          .contains(Modality.text)) {
        continue;
      }
      return (providerKey: provider, modelId: model);
    }
    return null;
  }

  int _targetContextCharBudget(ProviderConfig config, String modelId) {
    return compressRequestCharBudget(
      contextWindowTokens: ModelSpecResolver.instance
          .spec(config, modelId)
          .contextWindow,
      safeRequestChars: 24000,
    );
  }

  String _visibleTranscript(List<ChatMessage> history) {
    final lines = <String>[];
    for (final message in history) {
      final text = message.content.trim();
      if (text.isNotEmpty) {
        lines.add('${message.role == 'user' ? 'User' : 'Assistant'}: $text');
        continue;
      }
      final imageContext = message.imageGenerationContext;
      final hasImage = message.parts.any(
        (part) => part is ImagePart && !part.unavailable && part.uri.isNotEmpty,
      );
      if (imageContext != null && hasImage) {
        lines.add(
          'Assistant: [Generated image. Initial creative context: '
          '${imageContext.inheritedContext}. Applied requests: '
          '${imageContext.modificationLog.join(' -> ')}]',
        );
      }
    }
    return lines.join('\n\n');
  }

  String? _latestImageUri(Iterable<ChatMessage> messages) {
    final list = messages.toList(growable: false);
    for (var i = list.length - 1; i >= 0; i--) {
      for (var j = list[i].parts.length - 1; j >= 0; j--) {
        final part = list[i].parts[j];
        if (part is ImagePart &&
            !part.unavailable &&
            part.uri.trim().isNotEmpty) {
          return part.uri.trim();
        }
      }
    }
    return null;
  }

  String _truncateOldest(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '[Earlier visible messages omitted to fit the context window.]\n\n'
        '${value.substring(value.length - maxChars)}';
  }

  String _summaryPrompt(String transcript) {
    return '''Create a self-contained creative brief for an image-generation model from the visible conversation below.

Preserve:
- subject and character identity
- visual style, composition, dimensions, and setting
- constraints, exclusions, and decisions the user accepted
- the latest decision when earlier requests conflict

Do not mention the conversation or explain your work. Write in the user's language. Return only the creative brief.

<visible_conversation>
$transcript
</visible_conversation>''';
  }
}
