import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book_analysis.dart';
import 'package:anx_reader/models/book_analysis.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_core/chat_models.dart';

typedef ChapterContentFetcher = Future<String> Function(
    String href, {
    int? maxCharacters,
});

typedef ChapterListFetcher = Future<List<ChapterInfo>> Function();

class ChapterInfo {
  const ChapterInfo({required this.href, required this.label});
  final String href;
  final String label;
}

class BookAnalysisProgress {
  const BookAnalysisProgress({
    required this.current,
    required this.total,
    required this.phase,
    this.message,
  });

  final int current;
  final int total;
  final String phase; // 'chapter', 'merge', 'synthesis'
  final String? message;

  Map<String, dynamic> toJson() => {
        'current': current,
        'total': total,
        'phase': phase,
        if (message != null) 'message': message,
      };

  factory BookAnalysisProgress.fromJson(Map<String, dynamic> json) =>
      BookAnalysisProgress(
        current: json['current'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        phase: json['phase'] as String? ?? '',
        message: json['message'] as String?,
      );
}

class BookAnalysisService {
  BookAnalysisService({
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.chapterListFetcher,
    required this.chapterContentFetcher,
  });

  final int bookId;
  final String bookTitle;
  final String bookAuthor;
  final ChapterListFetcher chapterListFetcher;
  final ChapterContentFetcher chapterContentFetcher;

  final BookAnalysisDao _dao = bookAnalysisDao;
  bool _cancelled = false;
  Completer<void>? _cancelCompleter;

  /// Maximum characters per chapter for AI processing (speed optimization)
  static const int _chapterContentLimit = 2500;

  /// Minimum chapter content length for analysis (skip very short sections)
  static const int _minChapterLength = 80;

  void cancel() {
    _cancelled = true;
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
  }

  bool get isCancelled => _cancelled;

  Future<BookAnalysis?> getExistingAnalysis() => _dao.getByBookId(bookId);

  Stream<BookAnalysisProgress> analyze() async* {
    _cancelled = false;
    _cancelCompleter = Completer<void>();

    // Save initial state
    final now = DateTime.now().toIso8601String();
    await _dao.insertOrUpdate(BookAnalysis(
      bookId: bookId,
      status: 'analyzing',
      progress: jsonEncode(const BookAnalysisProgress(
        current: 0, total: 0, phase: 'chapter',
      ).toJson()),
      createdAt: now,
      updatedAt: now,
    ));

    try {
      // Stage 1: Get chapter list
      final chapters = await chapterListFetcher();
      if (chapters.isEmpty) {
        await _dao.updateStatus(bookId, 'error');
        return;
      }

      final totalChapters = chapters.length;
      final concurrency = Prefs().bookAnalysisConcurrency;

      // Stage 2: Analyze each chapter with concurrency control
      yield BookAnalysisProgress(
        current: 0, total: totalChapters, phase: 'chapter',
      );

      final chapterSummaries = <String, String>{}; // href -> summary
      final semaphore = _Semaphore(concurrency);
      final futures = <Future<void>>[];
      var completedCount = 0;
      final progressController = StreamController<BookAnalysisProgress>();

      void emitProgress(String label) {
        completedCount++;
        if (!_cancelled && !progressController.isClosed) {
          progressController.add(BookAnalysisProgress(
            current: completedCount,
            total: totalChapters,
            phase: 'chapter',
            message: label,
          ));
        }
      }

      for (var i = 0; i < chapters.length; i++) {
        if (_cancelled) break;

        final chapter = chapters[i];
        final index = i;

        final future = () async {
          // Ensure progress is always emitted exactly once per chapter
          bool emitted = false;
          void complete() {
            if (!emitted) {
              emitted = true;
              emitProgress(chapter.label);
            }
          }

          if (_cancelled) {
            complete();
            return;
          }

          // Fetch content first (no semaphore needed), with length limit for speed
          String content;
          try {
            content = await chapterContentFetcher(chapter.href,
                maxCharacters: _chapterContentLimit);
          } catch (e) {
            AnxLog.warning('Content fetch failed: ${chapter.href}: $e');
            complete();
            return;
          }
          if (content.length < _minChapterLength) {
            complete();
            return;
          }

          // Acquire semaphore for AI calls only
          await semaphore.acquire();
          try {
            if (_cancelled) {
              complete();
              return;
            }
            final prompt = generatePromptBookAnalysisChapter(
              bookTitle,
              chapter.label,
              index + 1,
              totalChapters,
              content,
            );

            final result = await _aiGenerateSingle(prompt.buildMessages());
            if (!_cancelled && result.trim().isNotEmpty) {
              chapterSummaries[chapter.href] = result;
            }
          } catch (e) {
            AnxLog.warning('Chapter analysis failed: ${chapter.href}: $e');
          } finally {
            semaphore.release();
            complete();
          }
        }();

        futures.add(future);
      }

      // Wait for all futures to complete, then close the progress controller
      // This ensures completedCount reaches totalChapters even if some
      // chapters were skipped (content too short, fetch failed, etc.)
      Future<void> closeController() async {
        await Future.wait(futures);
        if (!progressController.isClosed) {
          await progressController.close();
        }
      }

      final closer = closeController();

      // Yield progress as chapters complete
      try {
        await for (final progress in progressController.stream) {
          yield progress;
        }
      } finally {
        if (!progressController.isClosed) {
          await progressController.close();
        }
      }

      // Ensure closer completes
      await closer;

      if (_cancelled) {
        await _dao.updateStatus(bookId, 'cancelled');
        return;
      }

      if (chapterSummaries.isEmpty) {
        await _dao.updateStatus(bookId, 'error');
        return;
      }

      // Stage 3: Batch merge
      yield BookAnalysisProgress(
        current: 0, total: 1, phase: 'merge',
      );

      final allSummaries = chapterSummaries.values.join('\n\n---\n\n');
      final mergePrompt = generatePromptBookAnalysisBatchMerge(
        bookTitle,
        chapterSummaries.length,
        allSummaries,
      );

      final mergedSummary = await _aiGenerateSingle(mergePrompt.buildMessages());

      if (_cancelled) {
        await _dao.updateStatus(bookId, 'cancelled');
        return;
      }

      // Stage 4: Final synthesis
      yield BookAnalysisProgress(
        current: 0, total: 1, phase: 'synthesis',
      );

      // Collect representative passages (first 500 chars of first 5 chapters)
      final samplePassages = <String>[];
      final sampleCount = chapters.length.clamp(0, 5);
      for (var i = 0; i < sampleCount; i++) {
        try {
          final content = await chapterContentFetcher(
            chapters[i].href,
            maxCharacters: 500,
          );
          if (content.isNotEmpty) {
            samplePassages.add('[${chapters[i].label}] $content');
          }
        } catch (_) {}
      }

      final synthesisPrompt = generatePromptBookAnalysisFinalSynthesis(
        bookTitle,
        bookAuthor,
        mergedSummary,
        samplePassages.join('\n\n'),
      );

      final finalAnalysis = await _aiGenerateSingle(synthesisPrompt.buildMessages());

      if (_cancelled) {
        await _dao.updateStatus(bookId, 'cancelled');
        return;
      }

      // Save result
      final resultJson = jsonEncode({
        'final_synthesis': finalAnalysis,
        'merged_summary': mergedSummary,
        'chapter_count': chapterSummaries.length,
        'analyzed_at': DateTime.now().toIso8601String(),
      });

      await _dao.updateResult(bookId, resultJson);

      yield const BookAnalysisProgress(
        current: 1, total: 1, phase: 'completed',
      );
    } catch (e) {
      AnxLog.severe('Book analysis failed: $e');
      await _dao.updateStatus(bookId, 'error');
      rethrow;
    }
  }

  Future<String> _aiGenerateSingle(List<ChatMessage> messages) async {
    final buffer = StringBuffer();
    final completer = Completer<void>();

    final stream = aiGenerateStream(messages);

    final sub = stream.listen(
      (chunk) {
        buffer.write(chunk);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: false,
    );

    // Listen for cancellation — use a temporary subscription that we can
    // cancel when _aiGenerateSingle completes, avoiding callback accumulation.
    StreamSubscription<void>? cancelSub;
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      cancelSub = _cancelCompleter!.future.asStream().listen((_) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.completeError(Exception('Cancelled'));
        }
      });
    }

    try {
      await completer.future;
      return buffer.toString();
    } finally {
      await sub.cancel();
      await cancelSub?.cancel();
    }
  }
}

class _Semaphore {
  _Semaphore(this.maxCount) : _currentCount = maxCount;
  final int maxCount;
  int _currentCount;
  final _waitQueue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
