import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/image_generation_context.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/image_generation_context_service.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image generation context round-trips through message extras', () {
    const context = ImageGenerationContext(
      stageId: 'stage-1',
      inheritanceMode: ImageContextInheritanceMode.summary,
      inheritedContext: 'A red coat in a rainy city.',
      modificationLog: ['Make an illustration', 'Change the coat to blue'],
      summaryFallback: true,
      textOnlyFallback: true,
      inputImageUri: '/tmp/previous.png',
    );

    final message = ChatMessage(
      id: 'assistant-1',
      role: 'assistant',
      conversationId: 'conversation-1',
      extras: context.mergeIntoExtras(const {'other': 1}),
    );

    expect(message.imageGenerationContext?.toJson(), context.toJson());
    expect(message.extras['other'], 1);
    expect(
      message.imageGenerationContext!.buildImagePrompt(),
      contains('Change the coat to blue'),
    );
  });

  testWidgets(
    'full-conversation mode uses the selected branch and starts an image phase',
    (tester) async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      await settings.setImageContextInheritanceMode(
        ImageContextInheritanceMode.fullConversation,
      );
      addTearDown(settings.dispose);

      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              buildContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final builder = MessageBuilderService(
        chatService: ChatService(),
        contextProvider: buildContext,
      );
      final service = ImageGenerationContextService(builder);
      final oldBranch = ChatMessage(
        id: 'old-user',
        role: 'user',
        conversationId: 'conversation-1',
        content: 'Use a red coat',
        groupId: 'branch',
        version: 0,
      );
      final selectedBranch = ChatMessage(
        id: 'new-user',
        role: 'user',
        conversationId: 'conversation-1',
        content: 'Use a blue coat',
        groupId: 'branch',
        version: 1,
      );
      final assistant = ChatMessage(
        id: 'text-assistant',
        role: 'assistant',
        conversationId: 'conversation-1',
        content: 'The scene should be at night.',
        modelId: 'gpt-4o',
        providerId: 'OpenAI',
      );
      final request = ChatMessage(
        id: 'image-request',
        role: 'user',
        conversationId: 'conversation-1',
        content: 'Create the image',
      );

      final prepared = await service.prepare(
        messages: [oldBranch, selectedBranch, assistant, request],
        versionSelections: const {'branch': 1},
        settings: settings,
        providerKey: 'OpenAI',
        modelId: 'gpt-image-1',
        conversationId: 'conversation-1',
      );

      expect(prepared, isNotNull);
      final context = prepared!.context;
      expect(context.inheritedContext, contains('Use a blue coat'));
      expect(context.inheritedContext, isNot(contains('Use a red coat')));
      expect(context.inheritedContext, contains('at night'));
      expect(context.modificationLog, ['Create the image']);
      expect(context.stageId, 'image-request');
    },
  );

  testWidgets(
    'an image follow-up keeps the fixed context and appends the edit log',
    (tester) async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      await settings.setImageContextInheritanceMode(
        ImageContextInheritanceMode.fullConversation,
      );
      addTearDown(settings.dispose);

      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              buildContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final service = ImageGenerationContextService(
        MessageBuilderService(
          chatService: ChatService(),
          contextProvider: buildContext,
        ),
      );
      const firstContext = ImageGenerationContext(
        stageId: 'first-request',
        inheritanceMode: ImageContextInheritanceMode.summary,
        inheritedContext: 'A portrait with a red coat.',
        modificationLog: ['Create the portrait', 'Change the coat to blue'],
      );
      final generatedImage = ChatMessage(
        id: 'generated-image',
        role: 'assistant',
        conversationId: 'conversation-1',
        parts: const [ImagePart(uri: '/tmp/latest.png', mime: 'image/png')],
        extras: firstContext.mergeIntoExtras(),
        modelId: 'gpt-image-1',
        providerId: 'OpenAI',
      );
      final request = ChatMessage(
        id: 'follow-up',
        role: 'user',
        conversationId: 'conversation-1',
        content: 'Add a hat',
      );

      final prepared = await service.prepare(
        messages: [generatedImage, request],
        versionSelections: const {},
        settings: settings,
        providerKey: 'OpenAI',
        modelId: 'gpt-image-1',
        conversationId: 'conversation-1',
      );

      final context = prepared!.context;
      expect(context.inheritedContext, firstContext.inheritedContext);
      expect(context.modificationLog, [
        'Create the portrait',
        'Change the coat to blue',
        'Add a hat',
      ]);
      expect(context.inputImageUri, '/tmp/latest.png');
      expect(context.textOnlyFallback, isFalse);

      final fallback = await service.prepare(
        messages: [generatedImage, request],
        versionSelections: const {},
        settings: settings,
        providerKey: 'OpenAI',
        modelId: 'dall-e-3',
        conversationId: 'conversation-1',
      );
      expect(fallback!.context.textOnlyFallback, isTrue);
    },
  );

  test('image context settings persist through business preferences', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setImageContextModel('OpenAI', 'gpt-4o-mini');
    await settings.setImageContextInheritanceMode(
      ImageContextInheritanceMode.fullConversation,
    );
    settings.dispose();

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    addTearDown(reloaded.dispose);
    expect(reloaded.imageContextModelProvider, 'OpenAI');
    expect(reloaded.imageContextModelId, 'gpt-4o-mini');
    expect(
      reloaded.imageContextInheritanceMode,
      ImageContextInheritanceMode.fullConversation,
    );
  });
}
