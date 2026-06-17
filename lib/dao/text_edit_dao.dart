import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/text_edit.dart';

class TextEditDao extends BaseDao {
  TextEditDao();

  static const String table = 'tb_text_edit';

  Future<int> insertTextEdit(TextEdit textEdit) async {
    final now = DateTime.now().toIso8601String();
    return insert(table, textEdit.copyWith(createdAt: now).toMap());
  }

  Future<List<int>> batchInsertTextEdits(List<TextEdit> textEdits) async {
    return transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final ids = <int>[];
      for (final edit in textEdits) {
        final id = await txn.rawInsert(
          'INSERT INTO $table (book_id, chapter_href, original_text, edited_text, created_at) VALUES (?, ?, ?, ?, ?)',
          [edit.bookId, edit.chapterHref, edit.originalText, edit.editedText, now],
        );
        ids.add(id);
      }
      return ids;
    });
  }

  Future<List<TextEdit>> getByBookAndChapter(
      int bookId, String chapterHref) {
    return queryList(
      table,
      mapper: TextEdit.fromDb,
      where: 'book_id = ? AND chapter_href = ?',
      whereArgs: [bookId, chapterHref],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<TextEdit>> getByBookId(int bookId) {
    return queryList(
      table,
      mapper: TextEdit.fromDb,
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_href, created_at DESC',
    );
  }

  Future<void> deleteById(int id) async {
    await delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByBookAndChapter(
      int bookId, String chapterHref) async {
    await delete(
      table,
      where: 'book_id = ? AND chapter_href = ?',
      whereArgs: [bookId, chapterHref],
    );
  }

  Future<void> deleteByBookId(int bookId) async {
    await delete(table, where: 'book_id = ?', whereArgs: [bookId]);
  }
}

final textEditDao = TextEditDao();
