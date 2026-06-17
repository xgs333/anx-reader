class BookFanfic {
  final int? id;
  final int bookId;
  final String bookTitle;
  final String outline;
  final String content;
  final String title;
  final String? createdAt;
  final int? parentFanficId;
  final String? styleTemplate;

  BookFanfic({
    this.id,
    required this.bookId,
    required this.bookTitle,
    required this.outline,
    required this.content,
    required this.title,
    this.createdAt,
    this.parentFanficId,
    this.styleTemplate,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'book_title': bookTitle,
      'outline': outline,
      'content': content,
      'title': title,
      'created_at': createdAt,
      if (parentFanficId != null) 'parent_fanfic_id': parentFanficId,
      if (styleTemplate != null) 'style_template': styleTemplate,
    };
  }

  factory BookFanfic.fromDb(Map<String, dynamic> map) {
    return BookFanfic(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      bookTitle: map['book_title'] as String? ?? '',
      outline: map['outline'] as String? ?? '',
      content: map['content'] as String? ?? '',
      title: map['title'] as String? ?? '',
      createdAt: map['created_at'] as String?,
      parentFanficId: map['parent_fanfic_id'] as int?,
      styleTemplate: map['style_template'] as String?,
    );
  }

  BookFanfic copyWith({
    int? id,
    int? bookId,
    String? bookTitle,
    String? outline,
    String? content,
    String? title,
    String? createdAt,
    int? parentFanficId,
    String? styleTemplate,
  }) {
    return BookFanfic(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      outline: outline ?? this.outline,
      content: content ?? this.content,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      parentFanficId: parentFanficId ?? this.parentFanficId,
      styleTemplate: styleTemplate ?? this.styleTemplate,
    );
  }
}
