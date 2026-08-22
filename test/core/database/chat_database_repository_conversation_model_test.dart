import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';

void main() {
  late Directory root;
  late ChatDatabaseRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat_conversation_model_');
    repository = ChatDatabaseRepository.open(
      file: File('${root.path}/chat.sqlite'),
    );
    await repository.ensureReady();
  });

  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  Future<void> seed(Conversation conversation, List<ChatMessage> messages) {
    return repository.putMigrationBatch(
      conversations: [conversation],
      messages: [
        for (final (index, message) in messages.indexed)
          (message: message, messageOrder: index),
      ],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );
  }

  test(
    'returns the latest assistant model before trailing user messages',
    () async {
      const conversationId = 'conversation-a';
      final conversation = Conversation(id: conversationId, title: 'A');
      await seed(conversation, [
        ChatMessage(
          id: 'user-1',
          role: 'user',
          content: 'Question',
          conversationId: conversationId,
        ),
        ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'Answer',
          conversationId: conversationId,
          providerId: 'provider-a',
          modelId: 'model-1',
        ),
        ChatMessage(
          id: 'user-2',
          role: 'user',
          content: 'Follow-up',
          conversationId: conversationId,
        ),
      ]);

      expect(await repository.getLatestSelectedAssistantModel(conversationId), (
        providerId: 'provider-a',
        modelId: 'model-1',
      ));
    },
  );

  test('uses the selected revision of the latest assistant group', () async {
    const conversationId = 'conversation-versions';
    final conversation = Conversation(
      id: conversationId,
      title: 'Versions',
      versionSelections: const {'assistant-group': 1},
    );
    ChatMessage revision(String id, int version, String modelId) => ChatMessage(
      id: id,
      role: 'assistant',
      content: 'Answer $version',
      conversationId: conversationId,
      groupId: 'assistant-group',
      version: version,
      providerId: 'provider-a',
      modelId: modelId,
    );
    await seed(conversation, [
      ChatMessage(
        id: 'user-1',
        role: 'user',
        content: 'Question',
        conversationId: conversationId,
      ),
      revision('assistant-v1', 1, 'model-1'),
      revision('assistant-v2', 2, 'model-2'),
    ]);

    expect(await repository.getLatestSelectedAssistantModel(conversationId), (
      providerId: 'provider-a',
      modelId: 'model-1',
    ));
  });
}
