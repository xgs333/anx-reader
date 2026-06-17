import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/text_edit.dart';
import 'package:anx_reader/service/text_edit_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

class TextEditPage extends StatefulWidget {
  const TextEditPage({
    super.key,
    required this.book,
    required this.chapterHref,
    required this.originalContent,
  });

  final Book book;
  final String chapterHref;
  final String originalContent;

  @override
  State<TextEditPage> createState() => _TextEditPageState();
}

class _TextEditPageState extends State<TextEditPage> {
  late TextEditingController _textController;
  List<TextEdit> _existingEdits = [];
  bool _hasChanges = false;
  bool _isSaving = false;

  /// Normalized chapter href with fragment stripped.
  /// The TOC href may include a fragment (e.g. "chapter1.xhtml#section1"),
  /// but the JS side uses section.id (manifest href without fragment).
  /// Stripping the fragment ensures edits are found when applied.
  String get _normalizedHref => widget.chapterHref.split('#').first;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.originalContent);
    _textController.addListener(() {
      if (!_hasChanges) setState(() => _hasChanges = true);
    });
    _loadExistingEdits();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingEdits() async {
    try {
      final edits = await textEditService.loadEdits(
        widget.book.id,
        _normalizedHref,
      );
      if (mounted) setState(() => _existingEdits = edits);
    } catch (e) {
      AnxLog.warning('Failed to load existing edits: $e');
    }
  }

  Future<void> _saveEdits() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final newText = _textController.text;
      final edits = TextEditService.generateEdits(
        bookId: widget.book.id,
        chapterHref: _normalizedHref,
        oldText: widget.originalContent,
        newText: newText,
      );

      if (edits.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final saved = await textEditService.saveEdits(edits);
      final editsJson = TextEditService.buildEditsJson(saved);

      if (mounted) Navigator.pop(context, {'editsJson': editsJson});
    } catch (e) {
      AnxLog.severe('Failed to save edits: $e');
      if (mounted) {
        AnxToast.show(L10n.of(context).readingPageErrorEditingText);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _deleteEdit(TextEdit edit) async {
    try {
      await textEditService.deleteEdit(edit.id!);
      await _loadExistingEdits();
    } catch (e) {
      AnxLog.warning('Failed to delete edit: $e');
      if (mounted) {
        AnxToast.show(L10n.of(context).readingPageErrorEditingText);
      }
    }
  }

  void _deleteAllEdits() async {
    try {
      await textEditService.deleteAllForChapter(
        widget.book.id,
        _normalizedHref,
      );
      await _loadExistingEdits();
    } catch (e) {
      AnxLog.warning('Failed to delete all edits: $e');
      if (mounted) {
        AnxToast.show(L10n.of(context).readingPageErrorEditingText);
      }
    }
  }

  void _showEditManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditManagementSheet(
        edits: _existingEdits,
        onDelete: _deleteEdit,
        onDeleteAll: _deleteAllEdits,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readingPageEditText),
        actions: [
          if (_existingEdits.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: l10n.textEditManageEdits,
              onPressed: _showEditManagement,
            ),
          TextButton(
            onPressed: _hasChanges && !_isSaving ? _saveEdits : null,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.textEditSave),
          ),
        ],
      ),
      body: TextField(
        controller: _textController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 16, height: 1.6),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(16),
          border: InputBorder.none,
          hintText: l10n.textEditHint,
        ),
      ),
    );
  }
}

class _EditManagementSheet extends StatelessWidget {
  const _EditManagementSheet({
    required this.edits,
    required this.onDelete,
    required this.onDeleteAll,
  });

  final List<TextEdit> edits;
  final void Function(TextEdit) onDelete;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    l10n.textEditManageEdits,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (edits.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.textEditDeleteAll),
                            content: Text(l10n.textEditDeleteAllConfirm),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(MaterialLocalizations.of(context)
                                    .cancelButtonLabel),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.pop(context);
                                  onDeleteAll();
                                },
                                child: Text(l10n.textEditDeleteAll),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Text(
                        l10n.textEditDeleteAll,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: edits.isEmpty
                  ? Center(child: Text(l10n.textEditNoEdits))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: edits.length,
                      itemBuilder: (context, index) {
                        final edit = edits[index];
                        return _EditTile(
                          edit: edit,
                          onDelete: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(l10n.textEditDeleteEdit),
                                content: Text(l10n.textEditDeleteConfirm),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(
                                        MaterialLocalizations.of(context)
                                            .cancelButtonLabel),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.pop(context);
                                      onDelete(edit);
                                    },
                                    child: Text(l10n.textEditDeleteEdit),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EditTile extends StatelessWidget {
  const _EditTile({
    required this.edit,
    required this.onDelete,
  });

  final TextEdit edit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (edit.originalText.isNotEmpty) ...[
              Text(
                l10n.textEditOriginal,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.red,
                    ),
              ),
              Text(
                edit.originalText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 4),
            ],
            if (edit.editedText.isNotEmpty) ...[
              Text(
                l10n.textEditEdited,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.green,
                    ),
              ),
              Text(
                edit.editedText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.green),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.red,
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
