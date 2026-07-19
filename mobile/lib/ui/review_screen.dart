import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    required this.api,
    required this.bookId,
    required this.pin,
    super.key,
    this.analysisJobId,
  });
  final ApiClient api;
  final int bookId;
  final String pin;
  final int? analysisJobId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  BookDetail? _book;
  String _phase = '正在检查照片质量';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (widget.analysisJobId != null) {
        await _waitForJob(widget.analysisJobId!);
      }
      _book = await widget.api.getBook(widget.bookId);
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _waitForJob(int jobId) async {
    const phases = ['正在检查照片质量', '正在辨认每一页文字', '正在理解故事顺序', '正在准备双语内容'];
    var tick = 0;
    while (mounted) {
      final job = await widget.api.getJob(jobId);
      final status = job['status'] as String;
      if (status == 'succeeded') return;
      if (status == 'failed') {
        throw ApiException(job['error']?.toString() ?? '故事分析失败，请重试');
      }
      setState(() => _phase = phases[tick++ % phases.length]);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _saveAndConfirm() async {
    final book = _book;
    if (book == null) return;
    if (book.title.trim().isEmpty) {
      showMessage(context, '请填写故事标题', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveReview(book, widget.pin);
      await widget.api.confirmBook(
        book.id,
        'audio-${const Uuid().v4()}',
        widget.pin,
      );
      if (!mounted) return;
      showMessage(context, '校对完成，雪狐正在准备朗读声音');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      appBar: AppBar(
        title: const Text('家长校对'),
        backgroundColor: BraveColors.polar,
      ),
      bottomNavigationBar: book == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(18),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveAndConfirm,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.graphic_eq),
                label: Text(_saving ? '正在保存…' : '确认内容并准备朗读'),
              ),
            ),
      body: AuroraBackground(
        dark: false,
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: FrostedPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: BraveColors.coral,
                        ),
                        const SizedBox(height: 14),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _start();
                          },
                          child: const Text('重新检查'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : book == null
            ? _AnalysisProgress(phase: _phase)
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
                children: [
                  _CompletenessCard(book: book),
                  const SizedBox(height: 18),
                  FrostedPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '故事名片',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: book.title,
                          decoration: const InputDecoration(labelText: '故事标题'),
                          onChanged: (value) => book.title = value,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: book.summary,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(labelText: '故事简介'),
                          onChanged: (value) => book.summary = value,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Text(
                        '逐页校对',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${book.pages.where((item) => !item.isCover).length} 页',
                        style: const TextStyle(color: BraveColors.mist),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...book.pages
                      .where((item) => !item.isCover)
                      .map(
                        (page) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _PageEditor(api: widget.api, page: page),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

class _AnalysisProgress extends StatelessWidget {
  const _AnalysisProgress({required this.phase});
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: FrostedPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SnowFoxMark(size: 94),
              const SizedBox(height: 24),
              const Text(
                '雪狐正在读这本书',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  phase,
                  key: ValueKey(phase),
                  style: const TextStyle(color: BraveColors.auroraDeep),
                ),
              ),
              const SizedBox(height: 24),
              const LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(99)),
              ),
              const SizedBox(height: 14),
              const Text(
                '可以暂时离开，服务器会继续处理',
                style: TextStyle(color: BraveColors.mist, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletenessCard extends StatelessWidget {
  const _CompletenessCard({required this.book});
  final BookDetail book;

  String get title => switch (book.completenessStatus) {
    'likely_complete' => '看起来已经完整',
    'needs_review' => '有几处需要家长看看',
    _ => '暂时无法判断是否完整',
  };

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                book.completenessStatus == 'likely_complete'
                    ? Icons.verified_rounded
                    : Icons.fact_check_outlined,
                color: BraveColors.auroraDeep,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (book.completenessIssues.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...book.completenessIssues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(
                        color: BraveColors.coral,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Expanded(child: Text(issue)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: book.completenessStatus,
            decoration: const InputDecoration(labelText: '家长最终确认'),
            items: const [
              DropdownMenuItem(value: 'likely_complete', child: Text('确认完整')),
              DropdownMenuItem(value: 'needs_review', child: Text('仍需检查')),
              DropdownMenuItem(value: 'unknown', child: Text('无法判断')),
            ],
            onChanged: (value) =>
                book.completenessStatus = value ?? book.completenessStatus,
          ),
        ],
      ),
    );
  }
}

class _PageEditor extends StatelessWidget {
  const _PageEditor({required this.api, required this.page});
  final ApiClient api;
  final BookPageData page;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 58,
            height: 66,
            child: Image.network(
              api.absoluteUrl(page.thumbnailUrl),
              headers: api.authHeaders,
              fit: BoxFit.cover,
            ),
          ),
        ),
        title: Text(
          '第 ${page.orderIndex} 页',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          page.qualityIssues.isEmpty ? '文字和图片已识别' : page.qualityIssues.first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          TextFormField(
            initialValue: page.originalText,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '原文'),
            onChanged: (value) => page.originalText = value,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: page.zhText,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '中文朗读'),
            onChanged: (value) => page.zhText = value,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: page.enText,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'English reading'),
            onChanged: (value) => page.enText = value,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: page.explanation,
            decoration: const InputDecoration(labelText: '给家长看的儿童化简释'),
            onChanged: (value) => page.explanation = value,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: page.question,
            decoration: const InputDecoration(labelText: '亲子理解问题'),
            onChanged: (value) => page.question = value,
          ),
        ],
      ),
    );
  }
}
