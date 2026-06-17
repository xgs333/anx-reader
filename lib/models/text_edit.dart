class TextEdit {
  final int? id;
  final int bookId;
  final String chapterHref;
  final String originalText;
  final String editedText;
  final String? createdAt;

  TextEdit({
    this.id,
    required this.bookId,
    required this.chapterHref,
    required this.originalText,
    required this.editedText,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'chapter_href': chapterHref,
      'original_text': originalText,
      'edited_text': editedText,
      'created_at': createdAt,
    };
  }

  factory TextEdit.fromDb(Map<String, dynamic> map) {
    return TextEdit(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      chapterHref: map['chapter_href'] as String? ?? '',
      originalText: map['original_text'] as String? ?? '',
      editedText: map['edited_text'] as String? ?? '',
      createdAt: map['created_at'] as String?,
    );
  }

  TextEdit copyWith({
    int? id,
    int? bookId,
    String? chapterHref,
    String? originalText,
    String? editedText,
    String? createdAt,
  }) {
    return TextEdit(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterHref: chapterHref ?? this.chapterHref,
      originalText: originalText ?? this.originalText,
      editedText: editedText ?? this.editedText,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
