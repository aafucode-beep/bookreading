import 'models.dart';

List<String> readingLanguages(ReadingMode mode, ManifestPageData page) {
  final languages = switch (mode) {
    ReadingMode.follow => <String>['original'],
    ReadingMode.chinese => <String>['zh'],
    ReadingMode.english => <String>['en'],
    ReadingMode.zhThenEn => <String>['zh', 'en'],
    ReadingMode.enThenZh => <String>['en', 'zh'],
  };
  return languages.where(page.audio.containsKey).toList(growable: false);
}
