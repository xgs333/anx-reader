import 'dart:async';

import 'package:anx_reader/dao/book_analysis.dart';
import 'package:anx_reader/models/book_analysis.dart';
import 'package:anx_reader/models/book_fanfic.dart';
import 'package:anx_reader/service/ai/book_analysis_service.dart';
import 'package:anx_reader/service/ai/fanfic_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Analysis state
class BookAnalysisState {
  const BookAnalysisState({
    this.analysis,
    this.progress,
    this.isAnalyzing = false,
    this.error,
  });

  final BookAnalysis? analysis;
  final BookAnalysisProgress? progress;
  final bool isAnalyzing;
  final String? error;

  BookAnalysisState copyWith({
    BookAnalysis? analysis,
    BookAnalysisProgress? progress,
    bool? isAnalyzing,
    String? error,
  }) {
    return BookAnalysisState(
      analysis: analysis ?? this.analysis,
      progress: progress ?? this.progress,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      error: error,
    );
  }
}

class BookAnalysisNotifier extends StateNotifier<BookAnalysisState> {
  BookAnalysisNotifier(this.ref) : super(const BookAnalysisState());

  final Ref ref;
  BookAnalysisService? _service;
  StreamSubscription<BookAnalysisProgress>? _subscription;

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _service?.cancel();
    } catch (_) {
      // ignore cancel errors
    }
    _service = null;
    state = const BookAnalysisState();
  }

  Future<void> loadExisting(int bookId) async {
    try {
      final analysis = await bookAnalysisDao.getByBookId(bookId);
      if (analysis != null && mounted) {
        state = state.copyWith(analysis: analysis);
      }
    } catch (_) {}
  }

  Future<void> startAnalysis({
    required int bookId,
    required String bookTitle,
    required String bookAuthor,
    required ChapterListFetcher chapterListFetcher,
    required ChapterContentFetcher chapterContentFetcher,
  }) async {
    if (state.isAnalyzing) return;

    _service = BookAnalysisService(
      bookId: bookId,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      chapterListFetcher: chapterListFetcher,
      chapterContentFetcher: chapterContentFetcher,
    );

    state = state.copyWith(
      isAnalyzing: true,
      error: null,
      progress: const BookAnalysisProgress(
        current: 0, total: 0, phase: 'chapter',
        message: 'Preparing...',
      ),
    );

    _subscription = _service!.analyze().listen(
      (progress) {
        if (!mounted) return;
        state = state.copyWith(progress: progress);
      },
      onError: (e) {
        if (!mounted) return;
        state = state.copyWith(
          isAnalyzing: false,
          error: e.toString(),
        );
      },
      onDone: () async {
        if (_service == null) return;
        final analysis = await _service!.getExistingAnalysis();
        if (!mounted) return;
        state = state.copyWith(
          isAnalyzing: false,
          analysis: analysis,
        );
      },
    );
  }

  void cancelAnalysis() {
    _service?.cancel();
    _subscription?.cancel();
    state = state.copyWith(isAnalyzing: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final bookAnalysisProvider =
    StateNotifierProvider.family<BookAnalysisNotifier, BookAnalysisState, int>(
  (ref, bookId) => BookAnalysisNotifier(ref),
);

// Fanfic state
class FanficState {
  const FanficState({
    this.fanfics = const [],
    this.isGenerating = false,
    this.currentContent,
    this.error,
  });

  final List<BookFanfic> fanfics;
  final bool isGenerating;
  final String? currentContent;
  final String? error;

  FanficState copyWith({
    List<BookFanfic>? fanfics,
    bool? isGenerating,
    String? currentContent,
    String? error,
  }) {
    return FanficState(
      fanfics: fanfics ?? this.fanfics,
      isGenerating: isGenerating ?? this.isGenerating,
      currentContent: currentContent ?? this.currentContent,
      error: error,
    );
  }
}

class FanficNotifier extends StateNotifier<FanficState> {
  FanficNotifier() : super(const FanficState());

  void reset() {
    state = const FanficState();
  }

  Future<void> loadExisting(int bookId) async {
    try {
      final service = FanficService(bookId: bookId, bookTitle: '');
      final fanfics = await service.getExistingFanfics();
      if (mounted) {
        state = state.copyWith(fanfics: fanfics);
      }
    } catch (_) {}
  }

  Future<void> generate({
    required int bookId,
    required String bookTitle,
    required String outline,
  }) async {
    if (state.isGenerating) return;

    state = state.copyWith(isGenerating: true, error: null, currentContent: null);

    final service = FanficService(bookId: bookId, bookTitle: bookTitle);

    try {
      final result = await service.generateFanfic(outline);
      if (!mounted) return;
      state = state.copyWith(
        isGenerating: false,
        fanfics: [result, ...state.fanfics],
        currentContent: result.content,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
      );
    }
  }

  Future<String?> exportToTxt(BookFanfic fanfic) async {
    final service = FanficService(bookId: fanfic.bookId, bookTitle: fanfic.bookTitle);
    return service.exportToTxt(fanfic);
  }

  Future<void> deleteFanfic(int bookId, int fanficId) async {
    final service = FanficService(bookId: bookId, bookTitle: '');
    try {
      await service.deleteFanfic(fanficId);
      state = state.copyWith(
        fanfics: state.fanfics.where((f) => f.id != fanficId).toList(),
      );
    } catch (_) {
      // DB delete failed, don't remove from local state
      rethrow;
    }
  }
}

final fanficProvider =
    StateNotifierProvider.family<FanficNotifier, FanficState, int>(
  (ref, bookId) => FanficNotifier(),
);
