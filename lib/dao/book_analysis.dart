import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book_analysis.dart';
import 'package:anx_reader/models/book_fanfic.dart';

class BookAnalysisDao extends BaseDao {
  BookAnalysisDao();

  static const String table = 'tb_book_analysis';

  Future<int> insertOrUpdate(BookAnalysis analysis) async {
    return await runTransaction(() async {
      final existing = await getByBookId(analysis.bookId);
      if (existing != null) {
        await updateAnalysis(existing.id!, analysis.toMap());
        return existing.id!;
      }
      final now = DateTime.now().toIso8601String();
      return insert(table, analysis.copyWith(
        createdAt: analysis.createdAt ?? now,
        updatedAt: now,
      ).toMap());
    });
  }

  Future<void> updateAnalysis(int id, Map<String, Object?> values) async {
    await update(table, values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStatus(int bookId, String status) async {
    final now = DateTime.now().toIso8601String();
    await update(
      table,
      {'status': status, 'updated_at': now},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> updateProgress(
      int bookId, String status, String progressJson) async {
    final now = DateTime.now().toIso8601String();
    await update(
      table,
      {'status': status, 'progress': progressJson, 'updated_at': now},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> updateResult(int bookId, String analysisJson) async {
    final now = DateTime.now().toIso8601String();
    await update(
      table,
      {
        'analysis_text': analysisJson,
        'status': 'completed',
        'updated_at': now,
      },
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<BookAnalysis?> getByBookId(int bookId) async {
    return querySingle(
      table,
      mapper: BookAnalysis.fromDb,
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<BookAnalysis>> getAll() async {
    return queryList(
      table,
      mapper: BookAnalysis.fromDb,
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> deleteByBookId(int bookId) async {
    await delete(table, where: 'book_id = ?', whereArgs: [bookId]);
  }
}

class BookFanficDao extends BaseDao {
  BookFanficDao();

  static const String table = 'tb_book_fanfic';

  Future<int> insertFanfic(BookFanfic fanfic) async {
    return insert(table, fanfic.toMap());
  }

  Future<List<BookFanfic>> getByBookId(int bookId) async {
    return queryList(
      table,
      mapper: BookFanfic.fromDb,
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
  }

  Future<BookFanfic?> getById(int id) async {
    return querySingle(
      table,
      mapper: BookFanfic.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteById(int id) async {
    await delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByBookId(int bookId) async {
    await delete(table, where: 'book_id = ?', whereArgs: [bookId]);
  }
}

final bookAnalysisDao = BookAnalysisDao();
final bookFanficDao = BookFanficDao();
