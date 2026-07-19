import 'package:brave_growth/core/models.dart';
import 'package:brave_growth/core/reading_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = ManifestPageData(
    id: 1,
    orderIndex: 1,
    imageUrl: 'file:///page.webp',
    thumbnailUrl: 'file:///thumb.webp',
    detectedLanguage: 'bilingual',
    originalText: '原文',
    zhText: '中文',
    enText: 'English',
    explanation: '解释',
    question: '问题',
    audio: {
      for (final language in ['original', 'zh', 'en'])
        language: AudioAssetData(
          language: language,
          url: 'file:///$language.wav',
          mimeType: 'audio/wav',
          sha256: language,
        ),
    },
  );

  test('五种阅读模式生成正确的逐页音频顺序', () {
    expect(readingLanguages(ReadingMode.follow, page), ['original']);
    expect(readingLanguages(ReadingMode.chinese, page), ['zh']);
    expect(readingLanguages(ReadingMode.english, page), ['en']);
    expect(readingLanguages(ReadingMode.zhThenEn, page), ['zh', 'en']);
    expect(readingLanguages(ReadingMode.enThenZh, page), ['en', 'zh']);
  });

  test('缺失语音会被安全跳过', () {
    page.audio.remove('en');
    expect(readingLanguages(ReadingMode.zhThenEn, page), ['zh']);
    expect(readingLanguages(ReadingMode.english, page), isEmpty);
  });
}
