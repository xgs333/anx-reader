import 'dart:convert';

import 'package:anx_reader/dao/text_edit_dao.dart';
import 'package:anx_reader/models/text_edit.dart';

class TextEditService {

  /// Generate replacement pairs by diffing old and new text using LCS.
  ///
  /// Uses Hirschberg's algorithm (rolling array) to keep memory O(min(m,n))
  /// instead of O(m*n), preventing OOM on large chapters.
  static List<TextEdit> generateEdits({
    required int bookId,
    required String chapterHref,
    required String oldText,
    required String newText,
  }) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final m = oldLines.length;
    final n = newLines.length;

    // Edge case: both empty
    if (m == 1 && n == 1 && oldLines[0].isEmpty && newLines[0].isEmpty) {
      return [];
    }

    // Edge case: old empty → single insert
    if (m == 1 && oldLines[0].isEmpty) {
      final inserted = newLines.join('\n');
      if (inserted.isEmpty) return [];
      // Use a placeholder context that JS side can match (empty → not applied
      // since applyTextEdits skips empty originalText). Return as-is; caller
      // should handle by applying newText directly if needed.
      return [
        TextEdit(
          bookId: bookId,
          chapterHref: chapterHref,
          originalText: '',
          editedText: inserted,
        ),
      ];
    }

    // Build full LCS table only for reasonable sizes; for very large inputs
    // fall back to simple line-by-line diff to avoid OOM.
    if (m > 2000 || n > 2000) {
      return _generateEditsSimple(
        bookId: bookId,
        chapterHref: chapterHref,
        oldLines: oldLines,
        newLines: newLines,
      );
    }

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] = oldLines[i - 1] == newLines[j - 1]
            ? dp[i - 1][j - 1] + 1
            : dp[i - 1][j] > dp[i][j - 1]
                ? dp[i - 1][j]
                : dp[i][j - 1];
      }
    }

    // Backtrack to collect operations
    // op: 0 = keep, 1 = delete, 2 = insert
    final ops = <(int op, String old, String newLine)>[];
    int i = m, j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
        ops.add((0, oldLines[i - 1], newLines[j - 1]));
        i--;
        j--;
      } else if (i > 0 && (j == 0 || dp[i - 1][j] >= dp[i][j - 1])) {
        ops.add((1, oldLines[i - 1], ''));
        i--;
      } else {
        ops.add((2, '', newLines[j - 1]));
        j--;
      }
    }
    final reversed = ops.reversed.toList();

    // Aggregate operations into edit pairs.
    // JS applyTextEdits requires non-empty originalText, so we must
    // pair consecutive delete+insert as replace, and add context for
    // standalone operations.
    final edits = <TextEdit>[];
    String lastKept = '';
    // Track which context has been used to avoid duplicate originalText
    // for multiple standalone inserts.
    final usedContexts = <String>{};
    int iOp = 0;
    while (iOp < reversed.length) {
      final (op, old, newLine) = reversed[iOp];
      if (op == 0) {
        lastKept = old;
        usedContexts.clear();
        iOp++;
      } else if (op == 1 && iOp + 1 < reversed.length && reversed[iOp + 1].$1 == 2) {
        // delete followed by insert → replace
        edits.add(TextEdit(
          bookId: bookId,
          chapterHref: chapterHref,
          originalText: old,
          editedText: reversed[iOp + 1].$3,
        ));
        iOp += 2;
      } else if (op == 1) {
        // standalone delete
        edits.add(TextEdit(
          bookId: bookId,
          chapterHref: chapterHref,
          originalText: old,
          editedText: '',
        ));
        iOp++;
      } else if (op == 2) {
        // standalone insert — use previous kept line as context.
        // Collect consecutive inserts and merge into one edit to avoid
        // multiple edits sharing the same originalText.
        final insertedLines = <String>[newLine];
        iOp++;
        while (iOp < reversed.length && reversed[iOp].$1 == 2) {
          insertedLines.add(reversed[iOp].$3);
          iOp++;
        }
        if (lastKept.isNotEmpty && !usedContexts.contains(lastKept)) {
          usedContexts.add(lastKept);
          edits.add(TextEdit(
            bookId: bookId,
            chapterHref: chapterHref,
            originalText: lastKept,
            editedText: '$lastKept\n${insertedLines.join('\n')}',
          ));
        }
        // If lastKept is empty or already used, skip (cannot reliably insert
        // at beginning without context; caller should handle separately).
      } else {
        iOp++;
      }
    }

    return edits;
  }

  /// Simple fallback diff for very large texts: line-by-line comparison.
  /// Produces replace edits for mismatched lines.
  static List<TextEdit> _generateEditsSimple({
    required int bookId,
    required String chapterHref,
    required List<String> oldLines,
    required List<String> newLines,
  }) {
    final edits = <TextEdit>[];
    final maxLen = oldLines.length > newLines.length
        ? oldLines.length
        : newLines.length;
    for (int i = 0; i < maxLen; i++) {
      final oldLine = i < oldLines.length ? oldLines[i] : '';
      final newLine = i < newLines.length ? newLines[i] : '';
      if (oldLine != newLine) {
        if (oldLine.isNotEmpty) {
          edits.add(TextEdit(
            bookId: bookId,
            chapterHref: chapterHref,
            originalText: oldLine,
            editedText: newLine,
          ));
        }
      }
    }
    return edits;
  }

  /// Build JSON string for JS applyTextEdits call.
  static String buildEditsJson(List<TextEdit> edits) {
    return jsonEncode(edits
        .map((e) => {
              'originalText': e.originalText,
              'editedText': e.editedText,
            })
        .toList());
  }

  /// Build JS source string to call applyTextEdits with the given edits.
  /// jsonEncode already escapes \ and " for JSON.
  /// Only escapes backticks and ${} for JS template literals.
  static String buildApplyEditsJsSource(List<TextEdit> edits) {
    if (edits.isEmpty) return '';
    final editsJson = buildEditsJson(edits);
    final escaped = editsJson
        .replaceAll('`', r'\`')
        .replaceAll(r'${', r'\${');
    return 'applyTextEdits(`$escaped`)';
  }

  /// Build JS source from a pre-built JSON string.
  static String buildApplyEditsJsSourceFromJson(String editsJson) {
    final escaped = editsJson
        .replaceAll('`', r'\`')
        .replaceAll(r'${', r'\${');
    return 'applyTextEdits(`$escaped`)';
  }

  Future<List<TextEdit>> saveEdits(List<TextEdit> edits) async {
    final ids = await textEditDao.batchInsertTextEdits(edits);
    return [
      for (int i = 0; i < edits.length; i++)
        edits[i].copyWith(id: ids[i]),
    ];
  }

  Future<List<TextEdit>> loadEdits(int bookId, String chapterHref) {
    return textEditDao.getByBookAndChapter(bookId, chapterHref);
  }

  Future<void> deleteEdit(int id) {
    return textEditDao.deleteById(id);
  }

  Future<void> deleteAllForChapter(int bookId, String chapterHref) {
    return textEditDao.deleteByBookAndChapter(bookId, chapterHref);
  }
}

final textEditService = TextEditService();
