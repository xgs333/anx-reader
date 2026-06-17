import 'dart:convert';

class CharacterRelation {
  final int? id;
  final int bookId;
  final String? graphJson;
  final String? createdAt;
  final String? updatedAt;

  CharacterRelation({
    this.id,
    required this.bookId,
    this.graphJson,
    this.createdAt,
    this.updatedAt,
  });

  /// Parsed graph data. Expected format:
  /// {
  ///   "nodes": [{"id":"char1","name":"Alice","role":"protagonist","desc":"..."}],
  ///   "edges": [{"from":"char1","to":"char2","relation":"friend","label":"挚友"}]
  /// }
  Map<String, dynamic>? get parsedGraph {
    if (graphJson == null || graphJson!.isEmpty) return null;
    try {
      return jsonDecode(graphJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> get nodes {
    final graph = parsedGraph;
    if (graph == null) return [];
    final raw = graph['nodes'];
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }
    return [];
  }

  List<Map<String, dynamic>> get edges {
    final graph = parsedGraph;
    if (graph == null) return [];
    final raw = graph['edges'];
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'graph_json': graphJson,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CharacterRelation.fromDb(Map<String, dynamic> map) {
    return CharacterRelation(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      graphJson: map['graph_json'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  CharacterRelation copyWith({
    int? id,
    int? bookId,
    String? graphJson,
    String? createdAt,
    String? updatedAt,
  }) {
    return CharacterRelation(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      graphJson: graphJson ?? this.graphJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
