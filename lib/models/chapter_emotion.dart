import 'dart:convert';

class ChapterEmotion {
  final int? id;
  final int bookId;
  final String chapterHref;
  final String? chapterLabel;
  final String? emotionJson;
  final String? createdAt;
  final String? updatedAt;

  ChapterEmotion({
    this.id,
    required this.bookId,
    required this.chapterHref,
    this.chapterLabel,
    this.emotionJson,
    this.createdAt,
    this.updatedAt,
  });

  /// Parsed emotion data. Expected format:
  /// {"joy": 0.3, "sadness": 0.5, "tension": 0.8, "anger": 0.1, "fear": 0.2}
  Map<String, double>? get parsedEmotion {
    if (emotionJson == null || emotionJson!.isEmpty) return null;
    try {
      final raw = jsonDecode(emotionJson!) as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return null;
    }
  }

  /// Dominant emotion label, or null if no data.
  String? get dominantEmotion {
    final parsed = parsedEmotion;
    if (parsed == null || parsed.isEmpty) return null;
    final sorted = parsed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'chapter_href': chapterHref,
      'chapter_label': chapterLabel,
      'emotion_json': emotionJson,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ChapterEmotion.fromDb(Map<String, dynamic> map) {
    return ChapterEmotion(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      chapterHref: map['chapter_href'] as String,
      chapterLabel: map['chapter_label'] as String?,
      emotionJson: map['emotion_json'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  ChapterEmotion copyWith({
    int? id,
    int? bookId,
    String? chapterHref,
    String? chapterLabel,
    String? emotionJson,
    String? createdAt,
    String? updatedAt,
  }) {
    return ChapterEmotion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterHref: chapterHref ?? this.chapterHref,
      chapterLabel: chapterLabel ?? this.chapterLabel,
      emotionJson: emotionJson ?? this.emotionJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
