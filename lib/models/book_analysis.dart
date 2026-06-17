import 'dart:convert';

class BookAnalysis {
  final int? id;
  final int bookId;
  final String? analysisText;
  final String status; // pending / analyzing / completed / failed
  final String? progress; // JSON: {"current":32,"total":156,"stage":"chapter"}
  final String? createdAt;
  final String? updatedAt;

  BookAnalysis({
    this.id,
    required this.bookId,
    this.analysisText,
    this.status = 'pending',
    this.progress,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'analysis_text': analysisText,
      'status': status,
      'progress': progress,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory BookAnalysis.fromDb(Map<String, dynamic> map) {
    return BookAnalysis(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      analysisText: map['analysis_text'] as String?,
      status: map['status'] as String? ?? 'pending',
      progress: map['progress'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  BookAnalysis copyWith({
    int? id,
    int? bookId,
    String? analysisText,
    String? status,
    String? progress,
    String? createdAt,
    String? updatedAt,
  }) {
    return BookAnalysis(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      analysisText: analysisText ?? this.analysisText,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic>? get parsedAnalysis {
    if (analysisText == null || analysisText!.isEmpty) return null;
    try {
      return jsonDecode(analysisText!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? get parsedProgress {
    if (progress == null || progress!.isEmpty) return null;
    try {
      return jsonDecode(progress!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
