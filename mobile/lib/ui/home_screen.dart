import 'dart:io';

import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/models.dart';
import '../core/offline_store.dart';
import '../core/theme.dart';
import 'capture_screen.dart';
import 'common.dart';
import 'reader_screen.dart';
import 'review_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, required this.onSignOut, super.key});
  final ApiClient api;
  final Future<void> Function() onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _offline = OfflineStore();
  List<BookSummary> _books = const [];
  Set<int> _downloaded = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.listBooks(),
        _offline.downloadedBookIds(),
      ]);
      _books = values[0] as List<BookSummary>;
      _downloaded = values[1] as Set<int>;
    } catch (error) {
      _error = '$error';
      _downloaded = await _offline.downloadedBookIds();
      final cached = <BookSummary>[];
      for (final id in _downloaded) {
        final manifest = await _offline.load(id);
        if (manifest != null) {
          cached.add(
            BookSummary(
              id: id,
              title: manifest.title,
              summary: manifest.summary,
              status: 'ready',
              pageCount: manifest.pages.length,
              coverUrl: manifest.coverUrl,
            ),
          );
        }
      }
      _books = cached;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newBook() async {
    final pin = await requestParentPin(context, title: '添加一本绘本');
    if (pin == null || !mounted) return;
    try {
      final bookId = await widget.api.createBook('新绘本', pin);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CaptureScreen(api: widget.api, bookId: bookId, pin: pin),
        ),
      );
      _refresh();
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  Future<void> _openBook(BookSummary book) async {
    if (book.status == 'ready') {
      OfflineManifestData? manifest;
      try {
        manifest = await widget.api.getManifest(book.id);
      } catch (_) {
        manifest = await _offline.load(book.id);
      }
      if (manifest == null || !mounted) {
        if (mounted) showMessage(context, '这本绘本还没有可用的离线内容', error: true);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(api: widget.api, manifest: manifest!),
        ),
      );
      return;
    }
    if (book.status == 'review_required') {
      final pin = await requestParentPin(context, title: '校对绘本');
      if (pin == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ReviewScreen(api: widget.api, bookId: book.id, pin: pin),
        ),
      );
      _refresh();
      return;
    }
    if (book.status == 'draft' ||
        book.status == 'uploading' ||
        book.status == 'failed') {
      final pin = await requestParentPin(context, title: '继续上传');
      if (pin == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CaptureScreen(api: widget.api, bookId: book.id, pin: pin),
        ),
      );
      _refresh();
      return;
    }
    showMessage(context, '雪狐还在准备故事，请稍后刷新');
  }

  Future<void> _download(BookSummary book) async {
    final progress = ValueNotifier(0.0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => AlertDialog(
          title: const Text('收藏到离线书架'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 14),
              Text('${(value * 100).round()}% · 正在收好图片和声音'),
            ],
          ),
        ),
      ),
    );
    try {
      final manifest = await widget.api.getManifest(book.id);
      await _offline.download(
        widget.api,
        manifest,
        onProgress: (done, total) {
          progress.value = done / total;
        },
      );
      _downloaded = await _offline.downloadedBookIds();
      if (mounted) showMessage(context, '已经收藏，可以断网阅读了');
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newBook,
        backgroundColor: BraveColors.coral,
        foregroundColor: BraveColors.midnight,
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text(
          '拍一本书',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: AuroraBackground(
        dark: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 205,
                backgroundColor: BraveColors.midnight,
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    onPressed: widget.onSignOut,
                    tooltip: '退出家长账号',
                    icon: const Icon(Icons.logout),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: AuroraBackground(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 48, 24, 22),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const SnowFoxMark(size: 68),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '今晚读什么？',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .7),
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Text(
                                    '勇敢成长',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: BraveColors.warning.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _downloaded.isEmpty
                          ? '暂时连不上家庭服务器：$_error'
                          : '当前离线，显示已经下载的绘本。',
                    ),
                  ),
                ),
              if (_loading)
                const SliverFillRemaining(child: BusyView('正在唤醒书架…'))
              else if (_books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SnowFoxMark(size: 94),
                          const SizedBox(height: 24),
                          const Text(
                            '书架还空着',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '拍下封面和每一页，雪狐会帮你读。',
                            style: TextStyle(
                              color: BraveColors.mist.withValues(alpha: .9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 110),
                  sliver: SliverList.separated(
                    itemCount: _books.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) => _BookCard(
                      api: widget.api,
                      book: _books[index],
                      downloaded: _downloaded.contains(_books[index].id),
                      onTap: () => _openBook(_books[index]),
                      onDownload: () => _download(_books[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.api,
    required this.book,
    required this.downloaded,
    required this.onTap,
    required this.onDownload,
  });
  final ApiClient api;
  final BookSummary book;
  final bool downloaded;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  String get statusLabel => switch (book.status) {
    'ready' => '可以阅读',
    'review_required' => '等待家长校对',
    'preparing_audio' => '正在准备声音',
    'analyzing' => '正在理解故事',
    'failed' => '需要重试',
    _ => '继续上传',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Hero(
                tag: 'book-cover-${book.id}',
                child: Container(
                  width: 92,
                  height: 118,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: BraveColors.ice,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: book.coverUrl == null
                      ? const Icon(
                          Icons.auto_stories,
                          size: 42,
                          color: BraveColors.auroraDeep,
                        )
                      : book.coverUrl!.startsWith('file:')
                      ? Image.file(
                          File.fromUri(Uri.parse(book.coverUrl!)),
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          api.absoluteUrl(book.coverUrl!),
                          headers: api.authHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.auto_stories, size: 42),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${book.pageCount} 页 · $statusLabel',
                      style: const TextStyle(color: BraveColors.mist),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: book.status == 'ready'
                                ? BraveColors.aurora.withValues(alpha: .22)
                                : BraveColors.ice,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (book.status == 'ready')
                          IconButton(
                            onPressed: downloaded ? null : onDownload,
                            tooltip: downloaded ? '已离线收藏' : '离线收藏',
                            icon: Icon(
                              downloaded
                                  ? Icons.download_done_rounded
                                  : Icons.download_for_offline_outlined,
                              color: downloaded
                                  ? BraveColors.auroraDeep
                                  : BraveColors.mist,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
