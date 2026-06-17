import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/book_analysis.dart';
import 'package:anx_reader/models/book_analysis.dart';
import 'package:anx_reader/models/book_fanfic.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:path_provider/path_provider.dart';

class FanficService {
  FanficService({
    required this.bookId,
    required this.bookTitle,
  });

  final int bookId;
  final String bookTitle;
  final BookAnalysisDao _analysisDao = bookAnalysisDao;
  final BookFanficDao _fanficDao = bookFanficDao;

  Future<BookAnalysis?> getAnalysis() => _analysisDao.getByBookId(bookId);

  Future<List<BookFanfic>> getExistingFanfics() =>
      _fanficDao.getByBookId(bookId);

  Future<BookFanfic> generateFanfic(String outline) async {
    final analysis = await _analysisDao.getByBookId(bookId);
    if (analysis == null || analysis.analysisText == null) {
      throw Exception('Book analysis not found. Please analyze the book first.');
    }

    final analysisJson = analysis.analysisText!;
    final prompt = generatePromptBookAnalysisFanfic(
      bookTitle,
      analysisJson,
      outline,
    );

    final buffer = StringBuffer();
    final completer = Completer<void>();

    final stream = aiGenerateStream(prompt.buildMessages());

    final sub = stream.listen(
      (chunk) {
        buffer.write(chunk);
      },
      onDone: () => completer.complete(),
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: false,
    );

    await completer.future;
    await sub.cancel();
    final content = buffer.toString();

    // Extract title from first line if present
    String title = 'Fan Fiction';
    final lines = content.split('\n');
    if (lines.isNotEmpty) {
      final firstLine = lines.first.trim();
      if (firstLine.startsWith('#')) {
        title = firstLine.replaceFirst(RegExp(r'^#+\s*'), '');
      } else if (firstLine.isNotEmpty && firstLine.length < 100) {
        title = firstLine;
      }
    }

    final fanfic = BookFanfic(
      bookId: bookId,
      bookTitle: bookTitle,
      outline: outline,
      content: content,
      title: title,
      createdAt: DateTime.now().toIso8601String(),
    );

    final id = await _fanficDao.insertFanfic(fanfic);
    return fanfic.copyWith(id: id);
  }

  Future<String> exportToTxt(BookFanfic fanfic) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/fanfic_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final safeTitle = fanfic.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File('${exportDir.path}/$fileName');

    final buffer = StringBuffer();
    buffer.writeln(fanfic.title);
    buffer.writeln('=' * 40);
    buffer.writeln();
    buffer.writeln('Book: ${fanfic.bookTitle}');
    buffer.writeln('Outline: ${fanfic.outline}');
    buffer.writeln('Created: ${fanfic.createdAt}');
    buffer.writeln('=' * 40);
    buffer.writeln();
    buffer.writeln(fanfic.content);

    await file.writeAsString(buffer.toString(), encoding: utf8);
    return file.path;
  }

  Future<void> deleteFanfic(int id) => _fanficDao.deleteById(id);

  Future<void> deleteAllFanfics() => _fanficDao.deleteByBookId(bookId);
}
