import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/plan_import.dart';
import '../services/plan_import_service.dart';
import '../utils/activities.dart';
import '../utils/ai_service.dart';
import '../utils/plan_import_prompt.dart';
import '../widgets/main_scaffold.dart';

/// Profile → Import plan.
///
/// Flow: (1) get JSON — paste it, or paste plan text and let Gemini convert
/// it — (2) validate, (3) preview with checkboxes, (4) apply.
class PlanImportScreen extends StatefulWidget {
  const PlanImportScreen({super.key});

  @override
  State<PlanImportScreen> createState() => _PlanImportScreenState();
}

enum _Stage { input, preview, done }

class _PlanImportScreenState extends State<PlanImportScreen> with SingleTickerProviderStateMixin {
  final _jsonCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  late final TabController _tabs;

  _Stage _stage = _Stage.input;
  bool _busy = false;
  String? _busyLabel;
  List<ImportIssue> _issues = const [];
  PlanImport? _plan;
  ImportPreview? _preview;
  ImportSummary? _summary;

  List<String> _existingActivities = const [];
  List<String> _existingFolders = const [];

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadContext();
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    _planCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final uid = _uid;
    if (uid == null) return;
    final doc = await getFirestore().collection('user_settings').doc(uid).get();
    final data = doc.data() ?? {};
    final custom = List<String>.from(data['customActivities'] ?? const []);
    final archived = List<String>.from(data['archivedActivities'] ?? const []);
    if (!mounted) return;
    setState(() {
      _existingActivities = ({...kDefaultActivities, ...custom}..removeAll(archived)).toList();
      _existingFolders = List<String>.from(data['taskFolders'] ?? const []);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(
      text: PlanImportPrompt.buildPrompt(existingActivities: _existingActivities, existingFolders: _existingFolders),
    ));
    _snack('Prompt copied. Paste it into your LLM together with your plan, then paste the JSON back here.');
  }

  Future<void> _copyIssues() async {
    final text = _issues.map((i) => '- ${i.path}: ${i.message}').join('\n');
    await Clipboard.setData(ClipboardData(text: 'The Day Coach import rejected the JSON:\n$text\nPlease fix and return the full JSON again.'));
    _snack('Copied. Paste it back to your LLM to get a corrected version.');
  }

  Future<void> _previewJson() async {
    final uid = _uid;
    if (uid == null) return;
    final result = PlanImportParser.parse(_jsonCtrl.text);
    setState(() {
      _issues = result.issues;
      _plan = result.plan;
      _preview = null;
    });
    if (!result.ok) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Comparing with your data…';
    });
    try {
      final preview = await PlanImportService().preview(uid, result.plan!);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _stage = _Stage.preview;
      });
    } catch (e) {
      _snack('Could not build preview: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertWithAi() async {
    final text = _planCtrl.text.trim();
    if (text.isEmpty) {
      _snack('Paste your plan text first.');
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Asking Gemini to convert your plan…';
      _issues = const [];
    });
    try {
      final ai = AIService();
      var json = await ai.convertPlanToImport(
        planText: text,
        existingActivities: _existingActivities,
        existingFolders: _existingFolders,
      );
      var result = PlanImportParser.parse(json);
      if (!result.ok) {
        // One automatic repair round with the validator's feedback.
        setState(() => _busyLabel = 'Fixing ${result.errors.length} validation issue(s)…');
        json = await ai.convertPlanToImport(
          planText: text,
          existingActivities: _existingActivities,
          existingFolders: _existingFolders,
          fixErrors: result.errors.map((e) => '${e.path}: ${e.message}').join('\n'),
        );
        result = PlanImportParser.parse(json);
      }
      if (!mounted) return;
      _jsonCtrl.text = _prettify(json);
      _tabs.animateTo(0);
      setState(() => _busy = false);
      await _previewJson();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('AI conversion failed: $e');
      }
    }
  }

  String _prettify(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } catch (_) {
      return json;
    }
  }

  Future<void> _apply() async {
    final uid = _uid;
    final plan = _plan;
    final preview = _preview;
    if (uid == null || plan == null || preview == null) return;
    final selected = preview.items.where((i) => i.selected).map((i) => i.key).toSet();
    if (selected.isEmpty) {
      _snack('Nothing selected.');
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Applying…';
    });
    try {
      final summary = await PlanImportService().apply(uid, plan, selected);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _stage = _Stage.done;
      });
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import plan'),
        actions: [
          if (_stage != _Stage.input)
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _stage = _Stage.input),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit JSON'),
            ),
        ],
      ),
      body: Stack(
        children: [
          switch (_stage) {
            _Stage.input => _buildInput(context),
            _Stage.preview => _buildPreview(context),
            _Stage.done => _buildDone(context),
          },
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          const SizedBox(width: 14),
                          Text(_busyLabel ?? 'Working…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- stage 1 ------------------------------------------------------------

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Discuss your routine with any LLM, have it produce Day Coach JSON, paste it here. '
            'Or paste the plan text and let the built-in AI convert it. Nothing is saved until you review the preview.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Paste JSON', icon: Icon(Icons.data_object, size: 18)),
            Tab(text: 'Convert with AI', icon: Icon(Icons.auto_awesome, size: 18)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_buildJsonTab(context), _buildAiTab(context)],
          ),
        ),
      ],
    );
  }

  Widget _buildJsonTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _copyPrompt,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy prompt + format for your LLM'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showFormat(context),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('View format'),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                _jsonCtrl.text = PlanImportPrompt.schema.trim();
                _issues = const [];
              }),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Load example'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jsonCtrl,
          maxLines: 18,
          minLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '{ "version": 1, "habits": [...], "templates": [...] }',
            alignLabelWithHint: true,
            suffixIcon: _jsonCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _jsonCtrl.clear();
                      _issues = const [];
                    }),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _jsonCtrl.text.trim().isEmpty ? null : _previewJson,
          icon: const Icon(Icons.preview_outlined),
          label: const Text('Validate & preview'),
        ),
        if (_issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          _IssuesCard(issues: _issues, onCopy: _copyIssues),
        ],
        const SizedBox(height: 24),
        Text('Tips', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '• Short daily rituals (meditation, speech practice) belong in habits, not 10-minute blocks.\n'
          '• Mark anchors "locked" and flexible work time "workBlock" so top tasks land in the right place.\n'
          '• Re-import any time: items are matched by name and nothing is deleted.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildAiTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Paste the plan you wrote (Markdown, notes, anything). Gemini turns it into the import format; you still review before anything is saved.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _planCtrl,
          maxLines: 18,
          minLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '# Weekday schedule\n- Wake 7:00, sleep 23:00\n- 8:30 morning launch (anchor)\n- 8:40–10:00 deep work\n…',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _planCtrl.text.trim().isEmpty ? null : _convertWithAi,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Convert & preview'),
        ),
        if (_issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          _IssuesCard(issues: _issues, onCopy: _copyIssues),
        ],
      ],
    );
  }

  void _showFormat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import format v1'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              '${PlanImportPrompt.schema.trim()}\n\n${PlanImportPrompt.rules.trim()}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '${PlanImportPrompt.schema.trim()}\n\n${PlanImportPrompt.rules.trim()}'));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Format copied.');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ---- stage 2 ------------------------------------------------------------

  Widget _buildPreview(BuildContext context) {
    final preview = _preview!;
    final theme = Theme.of(context);
    const order = ['settings', 'activities', 'folders', 'habits', 'templates', 'tasks'];
    const titles = {
      'settings': 'Settings',
      'activities': 'Activities',
      'folders': 'Task folders',
      'habits': 'Habits',
      'templates': 'Day templates',
      'tasks': 'Tasks',
    };
    final warnings = _issues.where((i) => !i.isError).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
            children: [
              if (warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _IssuesCard(issues: warnings, onCopy: _copyIssues, compact: true),
                ),
              if (preview.notes.isNotEmpty)
                Card(
                  color: theme.colorScheme.tertiaryContainer,
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: preview.notes
                          .map((n) => Text('• $n', style: TextStyle(color: theme.colorScheme.onTertiaryContainer)))
                          .toList(),
                    ),
                  ),
                ),
              for (final s in order)
                if (preview.section(s).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(titles[s]!, style: theme.textTheme.titleMedium)),
                        TextButton(
                          onPressed: () {
                            final items = preview.section(s).where((i) => i.status != ImportStatus.same).toList();
                            final all = items.every((i) => i.selected);
                            setState(() {
                              for (final i in items) {
                                i.selected = !all;
                              }
                            });
                          },
                          child: const Text('Toggle all'),
                        ),
                      ],
                    ),
                  ),
                  ...preview.section(s).map((i) => _PreviewTile(item: i, onChanged: (v) => setState(() => i.selected = v))),
                ],
              if (preview.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing to import.'),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${preview.changeCount} change${preview.changeCount == 1 ? '' : 's'} selected',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy || preview.changeCount == 0 ? null : _apply,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- stage 3 ------------------------------------------------------------

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _summary?.lines() ?? const ['Nothing changed'];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.check_circle_outline, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Plan imported', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        ...lines.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• $l', style: theme.textTheme.bodyLarge),
            )),
        const SizedBox(height: 24),
        Text(
          'Templates auto-apply to their weekdays from tomorrow on (today keeps what you already planned). '
          'Use "Plan tomorrow" tonight to pick your top tasks and place them into the work blocks.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                Navigator.popUntil(context, (r) => r.isFirst);
                MainScaffold.selectTab(MainTab.habits);
              },
              child: const Text('Open Habits'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/template'),
              child: const Text('Open templates'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.popUntil(context, (r) => r.isFirst);
                MainScaffold.selectTab(MainTab.today);
              },
              child: const Text('Go to Today'),
            ),
          ],
        ),
      ],
    );
  }
}

class _IssuesCard extends StatelessWidget {
  final List<ImportIssue> issues;
  final VoidCallback onCopy;
  final bool compact;
  const _IssuesCard({required this.issues, required this.onCopy, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = issues.where((i) => i.isError).toList();
    final warnings = issues.where((i) => !i.isError).toList();
    final isError = errors.isNotEmpty;
    final bg = isError ? theme.colorScheme.errorContainer : Colors.amber.shade50;
    final fg = isError ? theme.colorScheme.onErrorContainer : Colors.brown.shade800;
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isError ? Icons.error_outline : Icons.warning_amber_outlined, color: fg, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isError
                        ? '${errors.length} problem${errors.length == 1 ? '' : 's'} — fix the JSON (or send these back to your LLM)'
                        : '${warnings.length} note${warnings.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                ),
                if (isError)
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: Icon(Icons.copy_outlined, size: 16, color: fg),
                    label: Text('Copy', style: TextStyle(color: fg)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...[...errors, ...warnings].take(compact ? 6 : 40).map(
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${i.path}: ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: fg)),
                        TextSpan(text: i.message, style: TextStyle(fontSize: 13, color: fg)),
                      ]),
                    ),
                  ),
                ),
            if (issues.length > (compact ? 6 : 40))
              Text('…and ${issues.length - (compact ? 6 : 40)} more', style: TextStyle(color: fg, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final ImportItem item;
  final ValueChanged<bool> onChanged;
  const _PreviewTile({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (item.status) {
      ImportStatus.add => ('New', theme.colorScheme.primary),
      ImportStatus.update => ('Update', Colors.orange.shade800),
      ImportStatus.same => ('Same', theme.colorScheme.outline),
    };
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: item.selected,
      onChanged: item.status == ImportStatus.same ? null : (v) => onChanged(v ?? false),
      title: Row(
        children: [
          Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      subtitle: item.detail.isEmpty ? null : Text(item.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
