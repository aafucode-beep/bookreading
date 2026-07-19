import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import 'common.dart';
import 'review_screen.dart';

class _CaptureItem {
  _CaptureItem({
    required this.keyValue,
    required this.isCover,
    required this.orderIndex,
    this.pageId,
    this.localPath,
    this.thumbnailUrl,
    this.issues = const [],
  }) : uploading = false;

  factory _CaptureItem.fromJson(Map<String, dynamic> json) => _CaptureItem(
    keyValue: json['key'] as String,
    isCover: json['is_cover'] as bool,
    orderIndex: json['order_index'] as int,
    localPath: json['local_path'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'key': keyValue,
    'is_cover': isCover,
    'order_index': orderIndex,
    'local_path': localPath,
  };
  final String keyValue;
  final bool isCover;
  int orderIndex;
  int? pageId;
  String? localPath;
  String? thumbnailUrl;
  bool uploading;
  List<String> issues;
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.api,
    required this.bookId,
    required this.pin,
    super.key,
  });
  final ApiClient api;
  final int bookId;
  final String pin;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final List<_CaptureItem> _items = [];
  bool _loading = true;
  bool _analyzing = false;
  String get _draftKey => 'capture_draft_${widget.bookId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.api.getBook(widget.bookId);
      _items
        ..clear()
        ..addAll(
          detail.pages.map(
            (page) => _CaptureItem(
              keyValue: 'server-${page.id}',
              isCover: page.isCover,
              orderIndex: page.orderIndex,
              pageId: page.id,
              thumbnailUrl: page.thumbnailUrl,
              issues: page.qualityIssues,
            ),
          ),
        );
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_draftKey);
      if (saved != null) {
        final pending = (jsonDecode(saved) as List)
            .map(
              (item) =>
                  _CaptureItem.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .where(
              (item) =>
                  item.localPath != null && File(item.localPath!).existsSync(),
            )
            .toList();
        _items.addAll(pending);
        for (final item in pending) {
          await _upload(item);
        }
      }
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePending() async {
    final preferences = await SharedPreferences.getInstance();
    final pending = _items
        .where((item) => item.pageId == null && item.localPath != null)
        .map((item) => item.toJson())
        .toList();
    if (pending.isEmpty) {
      await preferences.remove(_draftKey);
    } else {
      await preferences.setString(_draftKey, jsonEncode(pending));
    }
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: BraveColors.polar,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera,
                  color: BraveColors.auroraDeep,
                ),
                title: const Text('现在拍摄'),
                subtitle: const Text('请让书页铺平，避开灯光反射'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: BraveColors.auroraDeep,
                ),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _capture({required bool cover}) async {
    if (cover && _items.any((item) => item.isCover)) {
      showMessage(context, '封面已经拍好了，可先删除再重拍');
      return;
    }
    if (!cover && _items.where((item) => !item.isCover).length >= 64) {
      showMessage(context, '单本绘本最多 64 页', error: true);
      return;
    }
    final source = await _chooseSource();
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 2600,
      imageQuality: 94,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    final root = await getApplicationDocumentsDirectory();
    final key = _uuid.v4();
    final directory = Directory(
      '${root.path}/pending-captures/book-${widget.bookId}',
    );
    await directory.create(recursive: true);
    final target = File('${directory.path}/$key.jpg');
    await File(picked.path).copy(target.path);
    final item = _CaptureItem(
      keyValue: key,
      isCover: cover,
      orderIndex: cover ? 0 : _items.where((item) => !item.isCover).length + 1,
      localPath: target.path,
    );
    setState(() => _items.add(item));
    await _savePending();
    await _upload(item);
  }

  Future<void> _upload(_CaptureItem item) async {
    if (item.localPath == null || item.uploading || item.pageId != null) return;
    setState(() => item.uploading = true);
    try {
      final result = await widget.api.uploadPage(
        bookId: widget.bookId,
        file: File(item.localPath!),
        uploadKey: item.keyValue,
        orderIndex: item.orderIndex,
        isCover: item.isCover,
        pin: widget.pin,
      );
      item.pageId = result['id'] as int;
      item.issues = List<String>.from(
        result['quality_issues'] as List? ?? const [],
      );
      await _savePending();
    } catch (error) {
      if (mounted) showMessage(context, '上传暂停：$error。点击页面可重试。', error: true);
    } finally {
      if (mounted) setState(() => item.uploading = false);
    }
  }

  Future<void> _remove(_CaptureItem item) async {
    try {
      if (item.pageId != null) {
        await widget.api.deletePage(widget.bookId, item.pageId!, widget.pin);
      }
      if (item.localPath != null) {
        final localFile = File(item.localPath!);
        if (await localFile.exists()) {
          await localFile.delete();
        }
      }
      setState(() => _items.remove(item));
      var index = 1;
      for (final page in _items.where((value) => !value.isCover)) {
        page.orderIndex = index++;
      }
      await _savePending();
      final ids = _items
          .where((value) => !value.isCover && value.pageId != null)
          .map((value) => value.pageId!)
          .toList();
      if (ids.isNotEmpty) {
        await widget.api.reorderPages(widget.bookId, ids, widget.pin);
      }
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final body = _items.where((item) => !item.isCover).toList();
    if (newIndex > oldIndex) {
      newIndex--;
    }
    final item = body.removeAt(oldIndex);
    body.insert(newIndex, item);
    setState(() {
      _items.removeWhere((item) => !item.isCover);
      _items.addAll(body);
      for (var index = 0; index < body.length; index++) {
        body[index].orderIndex = index + 1;
      }
    });
    await _savePending();
    final ids = body
        .where((item) => item.pageId != null)
        .map((item) => item.pageId!)
        .toList();
    if (ids.length == body.length) {
      try {
        await widget.api.reorderPages(widget.bookId, ids, widget.pin);
      } catch (error) {
        if (mounted) showMessage(context, '$error', error: true);
      }
    }
  }

  Future<void> _analyze() async {
    if (_items.where((item) => !item.isCover && item.pageId != null).isEmpty) {
      showMessage(context, '请至少拍一页正文', error: true);
      return;
    }
    if (_items.any((item) => item.pageId == null)) {
      showMessage(context, '还有页面没有上传成功，请先重试', error: true);
      return;
    }
    setState(() => _analyzing = true);
    try {
      final jobId = await widget.api.analyzeBook(
        widget.bookId,
        'analyze-${_uuid.v4()}',
        widget.pin,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            api: widget.api,
            bookId: widget.bookId,
            pin: widget.pin,
            analysisJobId: jobId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Widget _image(_CaptureItem item) {
    if (item.localPath != null) {
      return Image.file(File(item.localPath!), fit: BoxFit.cover);
    }
    if (item.thumbnailUrl != null) {
      return Image.network(
        widget.api.absoluteUrl(item.thumbnailUrl!),
        headers: widget.api.authHeaders,
        fit: BoxFit.cover,
      );
    }
    return const ColoredBox(color: BraveColors.ice);
  }

  @override
  Widget build(BuildContext context) {
    final cover = _items.where((item) => item.isCover).firstOrNull;
    final pages = _items.where((item) => !item.isCover).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍摄绘本'),
        backgroundColor: BraveColors.polar,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: FilledButton.icon(
          onPressed: _analyzing ? null : _analyze,
          icon: _analyzing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_analyzing ? '正在送往雪屋…' : '检查完整性并理解故事'),
        ),
      ),
      body: AuroraBackground(
        dark: false,
        child: _loading
            ? const BusyView('正在找回已拍页面…')
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      child: FrostedPanel(
                        child: Row(
                          children: [
                            const SnowFoxMark(size: 58),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '先封面，再按顺序拍正文',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '书页铺平、四角入镜，避开手影和灯光。',
                                    style: TextStyle(
                                      color: BraveColors.mist.withValues(
                                        alpha: .9,
                                      ),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '封面',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (cover == null)
                            _AddTile(
                              label: '拍摄封面',
                              icon: Icons.book_outlined,
                              onTap: () => _capture(cover: true),
                            )
                          else
                            _CaptureTile(
                              item: cover,
                              image: _image(cover),
                              onRetry: () => _upload(cover),
                              onDelete: () => _remove(cover),
                            ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Text(
                                '正文',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${pages.length} / 64 页',
                                style: const TextStyle(color: BraveColors.mist),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: pages.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final item = pages[index];
                      return Padding(
                        key: ValueKey(item.keyValue),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: ReorderableDragStartListener(
                          index: index,
                          child: _CaptureTile(
                            item: item,
                            image: _image(item),
                            onRetry: () => _upload(item),
                            onDelete: () => _remove(item),
                          ),
                        ),
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
                      child: _AddTile(
                        label: '继续拍正文',
                        icon: Icons.add_a_photo_outlined,
                        onTap: () => _capture(cover: false),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: BraveColors.ice.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: SizedBox(
        height: 92,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: BraveColors.auroraDeep),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    ),
  );
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.item,
    required this.image,
    required this.onRetry,
    required this.onDelete,
  });
  final _CaptureItem item;
  final Widget image;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: SizedBox(width: 76, height: 84, child: image),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.isCover ? '绘本封面' : '第 ${item.orderIndex} 页',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 5),
                  if (item.uploading)
                    const Text(
                      '正在上传…',
                      style: TextStyle(color: BraveColors.auroraDeep),
                    )
                  else if (item.pageId == null)
                    InkWell(
                      onTap: onRetry,
                      child: const Text(
                        '上传暂停 · 点这里重试',
                        style: TextStyle(
                          color: Color(0xFF9E3B4D),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    Text(
                      item.issues.isEmpty ? '画面清晰' : item.issues.first,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: item.issues.isEmpty
                            ? BraveColors.mist
                            : const Color(0xFF9E6634),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (!item.isCover)
              const Icon(Icons.drag_handle, color: BraveColors.mist),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: BraveColors.mist),
            ),
          ],
        ),
      ),
    );
  }
}
