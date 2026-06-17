class ChapterSummary {
  final int? id;
  final int bookId;
  final String chapterHref;
  final String? chapterLabel;
  final String? summary;
  final String? createdAt;
  final String? updatedAt;

  ChapterSummary({
    this.id,
    required this.bookId,
    required this.chapterHref,
    this.chapterLabel,
    this.summary,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'chapter_href': chapterHref,
      'chapter_label': chapterLabel,
      'summary': summary,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ChapterSummary.fromDb(Map<String, dynamic> map) {
    return ChapterSummary(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      chapterHref: map['chapter_href'] as String,
      chapterLabel: map['chapter_label'] as String?,
      summary: map['summary'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  ChapterSummary copyWith({
    int? id,
    int? bookId,
    String? chapterHref,
    String? chapterLabel,
    String? summary,
    String? createdAt,
    String? updatedAt,
  }) {
    return ChapterSummary(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterHref: chapterHref ?? this.chapterHref,
      chapterLabel: chapterLabel ?? this.chapterLabel,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
