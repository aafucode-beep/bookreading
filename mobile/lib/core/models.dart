enum ReadingMode {
  follow('跟随内容'),
  chinese('中文'),
  english('English'),
  zhThenEn('先中文后英文'),
  enThenZh('先英文后中文');

  const ReadingMode(this.label);
  final String label;
}

class BookSummary {
  BookSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.status,
    required this.pageCount,
    this.coverUrl,
  });

  factory BookSummary.fromJson(Map<String, dynamic> json) => BookSummary(
    id: json['id'] as int,
    title: json['title'] as String? ?? '未命名绘本',
    summary: json['summary'] as String? ?? '',
    status: json['status'] as String? ?? 'draft',
    pageCount: json['page_count'] as int? ?? 0,
    coverUrl: json['cover_url'] as String?,
  );

  final int id;
  final String title;
  final String summary;
  final String status;
  final int pageCount;
  final String? coverUrl;
}

class BookPageData {
  BookPageData({
    required this.id,
    required this.orderIndex,
    required this.isCover,
    required this.thumbnailUrl,
    required this.originalText,
    required this.zhText,
    required this.enText,
    required this.explanation,
    required this.question,
    required this.qualityIssues,
  });

  factory BookPageData.fromJson(Map<String, dynamic> json) => BookPageData(
    id: json['id'] as int,
    orderIndex: json['order_index'] as int? ?? 0,
    isCover: json['is_cover'] as bool? ?? false,
    thumbnailUrl: json['thumbnail_url'] as String? ?? '',
    originalText: json['original_text'] as String? ?? '',
    zhText: json['zh_text'] as String? ?? '',
    enText: json['en_text'] as String? ?? '',
    explanation: json['explanation'] as String? ?? '',
    question: json['question'] as String? ?? '',
    qualityIssues: List<String>.from(
      json['quality_issues'] as List? ?? const [],
    ),
  );

  final int id;
  int orderIndex;
  final bool isCover;
  final String thumbnailUrl;
  String originalText;
  String zhText;
  String enText;
  String explanation;
  String question;
  final List<String> qualityIssues;
}

class BookDetail {
  BookDetail({
    required this.id,
    required this.title,
    required this.summary,
    required this.status,
    required this.completenessStatus,
    required this.completenessIssues,
    required this.pages,
  });

  factory BookDetail.fromJson(Map<String, dynamic> json) => BookDetail(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    status: json['status'] as String? ?? '',
    completenessStatus: json['completeness_status'] as String? ?? 'unknown',
    completenessIssues: List<String>.from(
      json['completeness_issues'] as List? ?? const [],
    ),
    pages: (json['pages'] as List? ?? const [])
        .map(
          (item) =>
              BookPageData.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  final int id;
  String title;
  String summary;
  final String status;
  String completenessStatus;
  final List<String> completenessIssues;
  final List<BookPageData> pages;
}

class AudioAssetData {
  AudioAssetData({
    required this.language,
    required this.url,
    required this.mimeType,
    required this.sha256,
  });

  factory AudioAssetData.fromJson(Map<String, dynamic> json) => AudioAssetData(
    language: json['language'] as String,
    url: json['url'] as String,
    mimeType: json['mime_type'] as String? ?? 'audio/mpeg',
    sha256: json['sha256'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'language': language,
    'url': url,
    'mime_type': mimeType,
    'sha256': sha256,
  };

  final String language;
  final String url;
  final String mimeType;
  final String sha256;
}

class ManifestPageData {
  ManifestPageData({
    required this.id,
    required this.orderIndex,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.detectedLanguage,
    required this.originalText,
    required this.zhText,
    required this.enText,
    required this.explanation,
    required this.question,
    required this.audio,
  });

  factory ManifestPageData.fromJson(Map<String, dynamic> json) =>
      ManifestPageData(
        id: json['id'] as int,
        orderIndex: json['order_index'] as int,
        imageUrl: json['image_url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String,
        detectedLanguage: json['detected_language'] as String? ?? 'unknown',
        originalText: json['original_text'] as String? ?? '',
        zhText: json['zh_text'] as String? ?? '',
        enText: json['en_text'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        question: json['question'] as String? ?? '',
        audio: (json['audio'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            AudioAssetData.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_index': orderIndex,
    'image_url': imageUrl,
    'thumbnail_url': thumbnailUrl,
    'detected_language': detectedLanguage,
    'original_text': originalText,
    'zh_text': zhText,
    'en_text': enText,
    'explanation': explanation,
    'question': question,
    'audio': audio.map((key, value) => MapEntry(key, value.toJson())),
  };

  final int id;
  final int orderIndex;
  String imageUrl;
  String thumbnailUrl;
  final String detectedLanguage;
  final String originalText;
  final String zhText;
  final String enText;
  final String explanation;
  final String question;
  final Map<String, AudioAssetData> audio;
}

class OfflineManifestData {
  OfflineManifestData({
    required this.bookId,
    required this.version,
    required this.title,
    required this.summary,
    required this.pages,
    this.coverUrl,
  });

  factory OfflineManifestData.fromJson(
    Map<String, dynamic> json,
  ) => OfflineManifestData(
    bookId: json['book_id'] as int,
    version: json['version'] as int,
    title: json['title'] as String,
    summary: json['summary'] as String? ?? '',
    coverUrl: json['cover_url'] as String?,
    pages: (json['pages'] as List)
        .map(
          (item) =>
              ManifestPageData.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'book_id': bookId,
    'version': version,
    'title': title,
    'summary': summary,
    'cover_url': coverUrl,
    'pages': pages.map((item) => item.toJson()).toList(),
  };

  final int bookId;
  final int version;
  final String title;
  final String summary;
  String? coverUrl;
  final List<ManifestPageData> pages;
}
