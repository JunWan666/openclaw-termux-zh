import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/local_model_chat_service.dart';

void main() {
  group('LocalModelChatService.normalizeAssistantContentForTest', () {
    test('splits think blocks into separate reasoning text', () {
      final result = LocalModelChatService.normalizeAssistantContentForTest(
        content: '<think>先分析问题</think>\n\n**最终答案**',
      );

      expect(result.reasoning, '先分析问题');
      expect(result.content, '**最终答案**');
    });

    test('keeps explicit reasoning and final answer together', () {
      final result = LocalModelChatService.normalizeAssistantContentForTest(
        content: '最后回答',
        explicitReasoning: '这是 reasoning_content',
      );

      expect(result.reasoning, '这是 reasoning_content');
      expect(result.content, '最后回答');
    });
  });

  group('LocalModelChatService.estimateTokenCountForTest', () {
    test('returns a positive estimate for chinese text', () {
      expect(
        LocalModelChatService.estimateTokenCountForTest('你好，请帮我总结这段文字'),
        greaterThan(0),
      );
    });

    test('returns a positive estimate for english markdown text', () {
      expect(
        LocalModelChatService.estimateTokenCountForTest(
          '## Title\n\nThis is a `code` example.',
        ),
        greaterThan(0),
      );
    });
  });
}
