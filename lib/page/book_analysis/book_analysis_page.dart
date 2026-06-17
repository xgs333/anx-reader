import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_analysis.dart';
import 'package:anx_reader/models/book_fanfic.dart';
import 'package:anx_reader/providers/book_analysis.dart';
import 'package:anx_reader/service/ai/book_analysis_service.dart';
import 'package:anx_reader/service/ai/epub_parser.dart';
import 'package:anx_reader/utils/toast/common.dart' show AnxToast;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookAnalysisPage extends ConsumerStatefulWidget {
  const BookAnalysisPage({
    super.key,
    required this.book,
    this.isFromFile = false,
    this.webViewController,
  });

  final Book book;
  final bool isFromFile;
  final InAppWebViewController? webViewController;

  @override
  ConsumerState<BookAnalysisPage> createState() => _BookAnalysisPageState();
}

class _BookAnalysisPageState extends ConsumerState<BookAnalysisPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _outlineController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outlineController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      ref.read(bookAnalysisProvider(widget.book.id).notifier).reset();
      ref.read(fanficProvider(widget.book.id).notifier).reset();
      await ref.read(bookAnalysisProvider(widget.book.id).notifier).loadExisting(widget.book.id);
      await ref.read(fanficProvider(widget.book.id).notifier).loadExisting(widget.book.id);
    } catch (_) {
      // ignore errors during data loading
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startAnalysis() async {
    if (widget.isFromFile) {
      await _startAnalysisFromFile();
    } else {
      await _startAnalysisFromBookshelf();
    }
  }

  Future<void> _startAnalysisFromBookshelf() async {
    final wvc = widget.webViewController;
    if (wvc == null) {
      if (mounted) {
        AnxToast.show(L10n.of(context).bookAnalysisOpenBookFirst);
      }
      return;
    }

    await ref.read(bookAnalysisProvider(widget.book.id).notifier).startAnalysis(
          bookId: widget.book.id,
          bookTitle: widget.book.title,
          bookAuthor: widget.book.author,
          chapterListFetcher: () async {
            final result = await wvc.evaluateJavascript(
              source: 'getAllChapters()',
            );
            if (result == null) return [];
            final jsonStr = result.toString();
            if (jsonStr.isEmpty || jsonStr == '[]') return [];
            final List<dynamic> json = jsonDecode(jsonStr);
            return json.map((e) => ChapterInfo(
              href: e['href'] as String,
              label: e['label'] as String,
            )).toList();
          },
          chapterContentFetcher: (href, {int? maxCharacters}) async {
            final opts = maxCharacters != null
                ? ', {maxChars: $maxCharacters}'
                : '';
            final escapedHref = href
                .replaceAll(r'\', r'\\')
                .replaceAll('"', r'\"')
                .replaceAll('\n', r'\n')
                .replaceAll('\r', r'\r');
            final result = await wvc.callAsyncJavaScript(
              functionBody:
                  'return await getChapterContentByHref("$escapedHref"$opts)',
            );
            return result?.value?.toString() ?? '';
          },
        );
  }

  Future<void> _startAnalysisFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return;

    try {
      if (file.extension?.toLowerCase() == 'epub') {
        await _analyzeEpubFile(path);
      } else if (file.extension?.toLowerCase() == 'txt') {
        await _analyzeTxtFile(path);
      }
    } catch (e) {
      if (mounted) {
        AnxToast.show('${L10n.of(context).bookAnalysisError}: $e');
      }
    }
  }

  Future<void> _analyzeEpubFile(String path) async {
    final epubInfo = await parseEpubFile(path);

    if (epubInfo.chapters.isEmpty) {
      if (mounted) {
        AnxToast.show(L10n.of(context).bookAnalysisError);
      }
      return;
    }

    final chapters = epubInfo.chapters
        .map((ch) => ChapterInfo(href: ch.href, label: ch.label))
        .toList();

    await ref.read(bookAnalysisProvider(widget.book.id).notifier).startAnalysis(
          bookId: widget.book.id,
          bookTitle: epubInfo.title.isEmpty ? widget.book.title : epubInfo.title,
          bookAuthor: epubInfo.author.isEmpty ? widget.book.author : epubInfo.author,
          chapterListFetcher: () async => chapters,
          chapterContentFetcher: (href, {int? maxCharacters}) async {
            final chapter = epubInfo.chapters.firstWhere(
              (ch) => ch.href == href,
              orElse: () => epubInfo.chapters.first,
            );
            final content = chapter.content;
            if (maxCharacters != null && content.length > maxCharacters) {
              return content.substring(0, maxCharacters);
            }
            return content;
          },
        );
  }

  Future<void> _analyzeTxtFile(String path) async {
    final content = await _readFileAsString(path);
    if (content.isEmpty) return;

    // Split TXT into chunks (approximate chapters)
    final chunks = _splitTextIntoChunks(content, 5000);
    final chapters = List.generate(
      chunks.length,
      (i) => ChapterInfo(
        href: 'chunk_$i',
        label: 'Part ${i + 1}',
      ),
    );

    await ref.read(bookAnalysisProvider(widget.book.id).notifier).startAnalysis(
          bookId: widget.book.id,
          bookTitle: widget.book.title,
          bookAuthor: widget.book.author,
          chapterListFetcher: () async => chapters,
          chapterContentFetcher: (href, {int? maxCharacters}) async {
            final index = int.tryParse(href.replaceFirst('chunk_', '')) ?? 0;
            if (index < 0 || index >= chunks.length) return '';
            final chunk = chunks[index];
            if (maxCharacters != null && chunk.length > maxCharacters) {
              return chunk.substring(0, maxCharacters);
            }
            return chunk;
          },
        );
  }

  List<String> _splitTextIntoChunks(String text, int chunkSize) {
    final chunks = <String>[];
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    var currentChunk = StringBuffer();

    for (final para in paragraphs) {
      if (currentChunk.length + para.length > chunkSize &&
          currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString().trim());
        currentChunk = StringBuffer();
      }
      currentChunk.writeln(para);
    }

    final last = currentChunk.toString().trim();
    if (last.isNotEmpty) {
      chunks.add(last);
    }

    return chunks.isEmpty ? [text] : chunks;
  }

  Future<void> _generateFanfic() async {
    final outline = _outlineController.text.trim();
    if (outline.isEmpty) {
      AnxToast.show(L10n.of(context).bookAnalysisOutlineRequired);
      return;
    }

    await ref.read(fanficProvider(widget.book.id).notifier).generate(
          bookId: widget.book.id,
          bookTitle: widget.book.title,
          outline: outline,
        );

    if (!mounted) return;
    _outlineController.clear();
    _tabController.animateTo(1);
  }

  Future<void> _exportFanfic(BookFanfic fanfic) async {
    final path = await ref.read(fanficProvider(widget.book.id).notifier).exportToTxt(fanfic);
    if (path != null && mounted) {
      AnxToast.show('${L10n.of(context).bookAnalysisExported}\n$path');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final analysisState = ref.watch(bookAnalysisProvider(widget.book.id));
    final fanficState = ref.watch(fanficProvider(widget.book.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiBookAnalysis),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.bookAnalysisTabAnalysis),
            Tab(text: l10n.bookAnalysisTabFanfic),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAnalysisTab(analysisState),
                _buildFanficTab(analysisState, fanficState),
              ],
            ),
    );
  }

  Widget _buildAnalysisTab(BookAnalysisState state) {
    final l10n = L10n.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status card
        _buildStatusCard(state),
        const SizedBox(height: 16),

        // Progress indicator
        if (state.isAnalyzing && state.progress != null) ...[
          _buildProgressIndicator(state.progress!),
          const SizedBox(height: 16),
        ],

        // Action buttons
        if (!state.isAnalyzing) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: Text(state.analysis != null
                  ? l10n.bookAnalysisReanalyze
                  : l10n.bookAnalysisStart),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(bookAnalysisProvider(widget.book.id).notifier).cancelAnalysis(),
              icon: const Icon(Icons.stop),
              label: Text(l10n.bookAnalysisCancel),
            ),
          ),
        ],

        // Analysis result
        if (state.analysis != null && !state.isAnalyzing) ...[
          const SizedBox(height: 16),
          _buildAnalysisResult(state.analysis!),
        ],
      ],
    );
  }

  Widget _buildStatusCard(BookAnalysisState state) {
    final l10n = L10n.of(context);
    final analysis = state.analysis;

    IconData icon;
    String statusText;
    Color color;

    if (state.isAnalyzing) {
      icon = Icons.sync;
      statusText = l10n.bookAnalysisStatusAnalyzing;
      color = Colors.orange;
    } else if (analysis == null) {
      icon = Icons.analytics_outlined;
      statusText = l10n.bookAnalysisStatusNotStarted;
      color = Colors.grey;
    } else if (analysis.status == 'completed') {
      icon = Icons.check_circle;
      statusText = l10n.bookAnalysisStatusCompleted;
      color = Colors.green;
    } else if (analysis.status == 'cancelled') {
      icon = Icons.cancel;
      statusText = l10n.bookAnalysisStatusCancelled;
      color = Colors.orange;
    } else if (analysis.status == 'error') {
      icon = Icons.error;
      statusText = l10n.bookAnalysisStatusError;
      color = Colors.red;
    } else {
      icon = Icons.hourglass_empty;
      statusText = analysis.status;
      color = Colors.grey;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.book.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(statusText, style: TextStyle(color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BookAnalysisProgress progress) {
    final l10n = L10n.of(context);

    String phaseText;
    switch (progress.phase) {
      case 'chapter':
        phaseText = l10n.bookAnalysisPhaseChapter;
        break;
      case 'merge':
        phaseText = l10n.bookAnalysisPhaseMerge;
        break;
      case 'synthesis':
        phaseText = l10n.bookAnalysisPhaseSynthesis;
        break;
      default:
        phaseText = progress.phase;
    }

    final progressValue = progress.total > 0
        ? progress.current / progress.total
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(phaseText, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progressValue),
            if (progress.total > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${progress.current} / ${progress.total}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (progress.message != null) ...[
              const SizedBox(height: 4),
              Text(
                progress.message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResult(BookAnalysis analysis) {
    final l10n = L10n.of(context);

    if (analysis.analysisText == null) {
      return const SizedBox.shrink();
    }

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(analysis.analysisText!) as Map<String, dynamic>;
    } catch (_) {}

    if (data == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(analysis.analysisText!),
        ),
      );
    }

    final synthesis = data['final_synthesis'] as String? ?? '';
    final chapterCount = data['chapter_count'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.bookAnalysisResult, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.bookAnalysisChaptersAnalyzed}: $chapterCount',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(),
                Text(synthesis),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFanficTab(BookAnalysisState analysisState, FanficState fanficState) {
    final l10n = L10n.of(context);
    final hasAnalysis = analysisState.analysis?.status == 'completed';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Outline input
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bookAnalysisOutlineTitle,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _outlineController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: l10n.bookAnalysisOutlineHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: hasAnalysis && !fanficState.isGenerating
                        ? _generateFanfic
                        : null,
                    icon: fanficState.isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit),
                    label: Text(fanficState.isGenerating
                        ? l10n.bookAnalysisGenerating
                        : l10n.bookAnalysisGenerateFanfic),
                  ),
                ),
                if (!hasAnalysis) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.bookAnalysisAnalyzeFirst,
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Error
        if (fanficState.error != null) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                fanficState.error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ),
        ],

        // Current generation
        if (fanficState.currentContent != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bookAnalysisCurrentFanfic,
                      style: Theme.of(context).textTheme.titleSmall),
                  const Divider(),
                  SelectableText(fanficState.currentContent!),
                ],
              ),
            ),
          ),
        ],

        // Existing fanfics
        if (fanficState.fanfics.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.bookAnalysisExistingFanfics,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...fanficState.fanfics.map((fanfic) => _buildFanficCard(fanfic)),
        ],
      ],
    );
  }

  Widget _buildFanficCard(BookFanfic fanfic) {
    final l10n = L10n.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(fanfic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          fanfic.outline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(fanfic.content),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _exportFanfic(fanfic),
                      icon: const Icon(Icons.save_alt),
                      label: Text(l10n.bookAnalysisExport),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await ref.read(fanficProvider(widget.book.id).notifier).deleteFanfic(
                              fanfic.bookId,
                              fanfic.id!,
                            );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.bookAnalysisDelete),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<String> _readFileAsString(String path) async {
  final file = File(path);
  try {
    return await file.readAsString();
  } catch (_) {
    try {
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      throw Exception('Failed to read file: $e');
    }
  }
}

