import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_model_service.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:uuid/uuid.dart';

class AiProviderDetailPage extends ConsumerStatefulWidget {
  final String? providerId; // null for new provider

  const AiProviderDetailPage({
    super.key,
    required this.providerId,
  });

  @override
  ConsumerState<AiProviderDetailPage> createState() =>
      _AiProviderDetailPageState();
}

class _AiProviderDetailPageState extends ConsumerState<AiProviderDetailPage> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _modelController;
  late TextEditingController _maxTokensController;
  late TextEditingController _extraHeadersController;

  AiProtocol _selectedProtocol = AiProtocol.openai;
  AiReasoningEffort _reasoningEffort = AiReasoningEffort.auto;
  double? _temperature;
  double? _topP;
  List<AiApiKey> _apiKeys = [];
  bool _isModified = false;
  bool _isFetchingModels = false;
  final GlobalKey _fetchButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    final provider = widget.providerId != null
        ? ref
            .read(aiProvidersProvider)
            .firstWhere((p) => p.id == widget.providerId)
        : null;

    _nameController = TextEditingController(text: provider?.title ?? '');
    _urlController = TextEditingController(text: provider?.url ?? '');
    _modelController = TextEditingController(text: provider?.model ?? '');
    _maxTokensController = TextEditingController(
        text: provider?.maxTokens?.toString() ?? '');
    _extraHeadersController = TextEditingController(
        text: provider?.extraHeaders ?? '');
    _selectedProtocol = provider?.protocol ?? AiProtocol.openai;
    _reasoningEffort = provider?.reasoningEffort ?? AiReasoningEffort.auto;
    _temperature = provider?.temperature;
    _topP = provider?.topP;
    _apiKeys = provider?.apiKeys.toList() ?? [];

    _nameController.addListener(() => setState(() => _isModified = true));
    _urlController.addListener(() => setState(() => _isModified = true));
    _modelController.addListener(() => setState(() => _isModified = true));
    _maxTokensController.addListener(() => setState(() => _isModified = true));
    _extraHeadersController.addListener(() => setState(() => _isModified = true));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    _extraHeadersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final provider = widget.providerId != null
        ? ref
            .watch(aiProvidersProvider)
            .firstWhere((p) => p.id == widget.providerId)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.providerId == null
            ? l10n.settingsAiProvidersAdd
            : l10n.settingsAiProviderName),
        actions: [
          if (_isModified)
            TextButton(
              onPressed: _saveProvider,
              child: Text(l10n.commonSave),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.settingsAiProviderName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Protocol Type
            Text(l10n.settingsAiProviderProtocol,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AnxSegmentedButton<AiProtocol>(
              selected: {_selectedProtocol},
              segments: [
                SegmentButtonItem(
                  value: AiProtocol.openai,
                  label: l10n.settingsAiProviderProtocolOpenai,
                ),
                SegmentButtonItem(
                  value: AiProtocol.claude,
                  label: l10n.settingsAiProviderProtocolClaude,
                ),
                SegmentButtonItem(
                  value: AiProtocol.gemini,
                  label: l10n.settingsAiProviderProtocolGemini,
                ),
              ],
              onSelectionChanged: (Set<AiProtocol> selection) {
                setState(() {
                  _selectedProtocol = selection.first;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 16),

            // API URL
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: l10n.settingsAiProviderUrl,
                border: const OutlineInputBorder(),
                helperText: _selectedProtocol == AiProtocol.openai
                    ? l10n.settingsAiProviderUrlHint
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Model
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: l10n.settingsAiProviderModel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_selectedProtocol == AiProtocol.openai) ...[
                  const SizedBox(width: 8),
                  AnxButton(
                    key: _fetchButtonKey,
                    onPressed: _isFetchingModels ? null : _fetchModels,
                    isLoading: _isFetchingModels,
                    child: Text(l10n.settingsAiProviderFetchModels),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            _buildAdvancedSettingsCard(context),
            const SizedBox(height: 16),

            // API Keys Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.settingsAiProviderApiKeys,
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addApiKey,
                  tooltip: l10n.settingsAiProviderAddKey,
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_apiKeys.isEmpty)
              FilledContainer(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        Icons.key_off_outlined,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(120),
                      ),
                      Text(
                        l10n.settingsAiProviderNoValidKeys,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(150),
                            ),
                        textAlign: TextAlign.center,
                      ),
                      AnxButton.icon(
                        onPressed: _addApiKey,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.settingsAiProviderAddKey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._apiKeys.asMap().entries.map((entry) {
                final index = entry.key;
                final apiKey = entry.value;
                return _buildApiKeyTile(apiKey, index);
              }),

            const SizedBox(height: 24),

            // Test Connection Button (at bottom)
            if (provider != null)
              SizedBox(
                width: double.infinity,
                child: AnxButton.outlined(
                  onPressed: _testConnection,
                  child: Text(l10n.settingsAiProviderTestConnection),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettingsCard(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.secondary;

    return FilledContainer(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.all(16),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: accent,
        collapsedIconColor: accent.withValues(alpha: 0.82),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 18,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsAdvanced,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        children: [
          // Reasoning Effort — only for OpenAI-compatible protocol
          if (_selectedProtocol == AiProtocol.openai) ...[
            DropdownButtonFormField<AiReasoningEffort>(
              value: _reasoningEffort,
              decoration: InputDecoration(
                labelText: l10n.settingsAiProviderReasoningEffort,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: AiReasoningEffort.auto,
                  child: Text(l10n.settingsAiProviderReasoningEffortAuto),
                ),
                DropdownMenuItem(
                  value: AiReasoningEffort.low,
                  child: Text(l10n.settingsAiProviderReasoningEffortLow),
                ),
                DropdownMenuItem(
                  value: AiReasoningEffort.medium,
                  child: Text(l10n.settingsAiProviderReasoningEffortMedium),
                ),
                DropdownMenuItem(
                  value: AiReasoningEffort.high,
                  child: Text(l10n.settingsAiProviderReasoningEffortHigh),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _reasoningEffort = value;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 10),
            _buildInfoRow(l10n.settingsAiProviderReasoningEffortHelp),
            const SizedBox(height: 16),
          ],

          // Temperature
          _buildSliderField(
            label: l10n.settingsAiProviderTemperature,
            value: _temperature,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            defaultValue: 1.0,
            onChanged: (v) => setState(() {
              _temperature = v;
              _isModified = true;
            }),
            onClear: () => setState(() {
              _temperature = null;
              _isModified = true;
            }),
          ),
          const SizedBox(height: 4),
          _buildInfoRow(l10n.settingsAiProviderTemperatureHelp),
          const SizedBox(height: 16),

          // Top P
          _buildSliderField(
            label: l10n.settingsAiProviderTopP,
            value: _topP,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            defaultValue: 0.95,
            onChanged: (v) => setState(() {
              _topP = v;
              _isModified = true;
            }),
            onClear: () => setState(() {
              _topP = null;
              _isModified = true;
            }),
          ),
          const SizedBox(height: 4),
          _buildInfoRow(l10n.settingsAiProviderTopPHelp),
          const SizedBox(height: 16),

          // Max Tokens
          TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.settingsAiProviderMaxTokens,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          _buildInfoRow(l10n.settingsAiProviderMaxTokensHelp),
          const SizedBox(height: 16),

          // Extra Headers
          TextField(
            controller: _extraHeadersController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.settingsAiProviderExtraHeaders,
              border: const OutlineInputBorder(),
              hintText: '{"X-Custom": "value"}',
            ),
          ),
          const SizedBox(height: 4),
          _buildInfoRow(l10n.settingsAiProviderExtraHeadersHelp),
        ],
      ),
    );
  }

  Widget _buildSliderField({
    required String label,
    required double? value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required VoidCallback onClear,
    double? defaultValue,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.titleSmall),
            ),
            Text(
              value != null ? value.toStringAsFixed(2) : '--',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
                tooltip: L10n.of(context).commonReset,
                visualDensity: VisualDensity.compact,
              ),
            if (value == null)
              IconButton(
                icon: const Icon(Icons.tune, size: 18),
                onPressed: () => onChanged(defaultValue ?? min),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        Slider(
          value: value ?? min,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: value != null ? onChanged : null,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyTile(AiApiKey apiKey, int index) {
    final l10n = L10n.of(context);
    bool obscureKey = true;

    return FilledContainer(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    apiKey.label?.isNotEmpty == true
                        ? apiKey.label!
                        : 'API Key ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: apiKey.enabled,
                  onChanged: (value) {
                    setState(() {
                      _apiKeys[index] = AiApiKey(
                        id: apiKey.id,
                        key: apiKey.key,
                        enabled: value,
                        label: apiKey.label,
                        createdAt: apiKey.createdAt,
                      );
                      _isModified = true;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteApiKey(index),
                  tooltip: l10n.commonDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setModalState) {
                return TextFormField(
                  initialValue: apiKey.key,
                  obscureText: obscureKey,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscureKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setModalState(() => obscureKey = !obscureKey);
                      },
                    ),
                  ),
                  onChanged: (value) {
                    _apiKeys[index] = AiApiKey(
                      id: apiKey.id,
                      key: value,
                      enabled: apiKey.enabled,
                      label: apiKey.label,
                      createdAt: apiKey.createdAt,
                    );
                    _isModified = true;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addApiKey() {
    final l10n = L10n.of(context);
    final labelController = TextEditingController();
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsAiProviderAddKey),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: l10n.settingsAiProviderKeyLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              if (keyController.text.isNotEmpty) {
                setState(() {
                  _apiKeys.add(AiApiKey(
                    id: const Uuid().v4(),
                    key: keyController.text,
                    enabled: true,
                    label: labelController.text.isNotEmpty
                        ? labelController.text
                        : null,
                    createdAt: DateTime.now(),
                  ));
                  _isModified = true;
                });
                Navigator.pop(context);
              }
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteApiKey(int index) async {
    final l10n = L10n.of(context);
    bool confirmed = false;

    await SmartDialog.show(
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.commonConfirm),
        content: Text(l10n.commonDelete),
        actions: [
          TextButton(
            onPressed: () {
              confirmed = false;
              SmartDialog.dismiss();
            },
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              confirmed = true;
              SmartDialog.dismiss();
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );

    if (confirmed) {
      setState(() {
        _apiKeys.removeAt(index);
        _isModified = true;
      });
    }
  }

  Future<void> _fetchModels() async {
    final l10n = L10n.of(context);
    final enabledKeys = _apiKeys.where((k) => k.enabled && k.key.isNotEmpty);
    if (enabledKeys.isEmpty || _urlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsAiProviderNoValidKeys)),
      );
      return;
    }

    setState(() => _isFetchingModels = true);

    try {
      final models = await fetchAiModels(
        url: _urlController.text.trim(),
        apiKey: enabledKeys.first.key,
      );

      if (!mounted) return;
      setState(() => _isFetchingModels = false);

      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsAiProviderNoModelsFound)),
        );
        return;
      }

      // Position the dropdown below the fetch button
      final renderBox =
          _fetchButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      final size = renderBox?.size ?? Size.zero;

      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          offset.dx,
          offset.dy + size.height,
          offset.dx + size.width,
          offset.dy + size.height + 1,
        ),
        constraints: BoxConstraints(
          minWidth: 220,
          maxHeight: MediaQuery.of(context).size.height * 0.4,
        ),
        items: models
            .map(
              (modelId) => PopupMenuItem<String>(
                value: modelId,
                child: Text(modelId),
              ),
            )
            .toList(),
      );

      if (selected != null) {
        _modelController.text = selected;
        setState(() => _isModified = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingModels = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n.settingsAiProviderFetchModelsFailed(e.toString())),
          ),
        );
      }
    }
  }

  AiProvider _buildProviderFromForm() {
    return AiProvider(
      id: widget.providerId ?? const Uuid().v4(),
      title: _nameController.text,
      url: _urlController.text,
      protocol: _selectedProtocol,
      enabled: true,
      isBuiltin: widget.providerId != null
          ? ref
              .read(aiProvidersProvider)
              .firstWhere((p) => p.id == widget.providerId)
              .isBuiltin
          : false,
      apiKeys: _apiKeys,
      model: _modelController.text,
      reasoningEffort: _reasoningEffort,
      temperature: _temperature,
      topP: _topP,
      maxTokens: int.tryParse(_maxTokensController.text.trim()),
      extraHeaders: _extraHeadersController.text.trim().isEmpty
          ? null
          : _extraHeadersController.text.trim(),
      keyIndex: 0,
      createdAt: widget.providerId != null
          ? ref
              .read(aiProvidersProvider)
              .firstWhere((p) => p.id == widget.providerId)
              .createdAt
          : DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _saveProvider() {
    final l10n = L10n.of(context);

    if (_nameController.text.isEmpty || _urlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonFailed)),
      );
      return;
    }

    final provider = _buildProviderFromForm();

    if (widget.providerId == null) {
      ref.read(aiProvidersProvider.notifier).addProvider(provider);
    } else {
      ref.read(aiProvidersProvider.notifier).updateProvider(provider);
    }

    setState(() => _isModified = false);
    Navigator.pop(context);
  }

  void _testConnection() {
    final l10n = L10n.of(context);
    String? effectiveId = widget.providerId;

    // Save any pending changes before testing so the provider has the latest config
    if (_isModified) {
      if (_nameController.text.isEmpty || _urlController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.commonFailed)),
        );
        return;
      }
      final provider = _buildProviderFromForm();
      effectiveId = provider.id;
      if (widget.providerId == null) {
        ref.read(aiProvidersProvider.notifier).addProvider(provider);
      } else {
        ref.read(aiProvidersProvider.notifier).updateProvider(provider);
      }
      setState(() => _isModified = false);
    }

    SmartDialog.show(
      onDismiss: () {
        cancelActiveAiRequest();
      },
      builder: (context) => AlertDialog(
        title: Text(l10n.commonTest),
        content: SizedBox(
          width: double.maxFinite,
          child: AiStream(
            prompt: generatePromptTest(),
            identifier: effectiveId,
            regenerate: true,
          ),
        ),
      ),
    );
  }
}
