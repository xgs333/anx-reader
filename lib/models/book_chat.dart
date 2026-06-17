class BookChatMessage {
  final int? id;
  final int bookId;
  final String role; // 'user' or 'assistant'
  final String content;
  final String? createdAt;

  BookChatMessage({
    this.id,
    required this.bookId,
    required this.role,
    required this.content,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'role': role,
      'content': content,
      'created_at': createdAt,
    };
  }

  factory BookChatMessage.fromDb(Map<String, dynamic> map) {
    return BookChatMessage(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      role: map['role'] as String,
      content: map['content'] as String? ?? '',
      createdAt: map['created_at'] as String?,
    );
  }
}
