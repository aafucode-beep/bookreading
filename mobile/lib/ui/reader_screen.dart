import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/reading_queue.dart';
import '../core/theme.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.api, required this.manifest, super.key});
  final ApiClient api;
  final OfflineManifestData manifest;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final AudioPlayer _player = AudioPlayer();
  var _mode = ReadingMode.follow;
  var _pageIndex = 0;
  var _playing = false;
  var _session = 0;
  String? _activeLanguage;

  ManifestPageData get page => widget.manifest.pages[_pageIndex];

  @override
  void dispose() {
    _session++;
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.manifest.pages.isEmpty) return;
    final session = ++_session;
    setState(() => _playing = true);
    unawaited(_run(session));
  }

  Future<void> _run(int session) async {
    try {
      while (mounted && _playing && session == _session) {
        final current = page;
        final languages = readingLanguages(_mode, current);
        if (languages.isEmpty) {
          throw StateError('这一页还没有${_mode.label}音频');
        }
        for (final language in languages) {
          if (!mounted || !_playing || session != _session) return;
          setState(() => _activeLanguage = language);
          final asset = current.audio[language]!;
          final uri = Uri.parse(widget.api.absoluteUrl(asset.url));
          final source = uri.scheme == 'file'
              ? AudioSource.file(File.fromUri(uri).path)
              : AudioSource.uri(uri, headers: widget.api.authHeaders);
          await _player.setAudioSource(source);
          await _player.play();
          if (!mounted || !_playing || session != _session) return;
          if (_player.processingState != ProcessingState.completed) return;
          await _player.pause();
        }
        if (_pageIndex >= widget.manifest.pages.length - 1) {
          setState(() {
            _playing = false;
            _activeLanguage = null;
          });
          return;
        }
        setState(() => _pageIndex++);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (error) {
      if (mounted && session == _session) {
        setState(() {
          _playing = false;
          _activeLanguage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pause() async {
    _session++;
    await _player.pause();
    if (mounted) {
      setState(() {
        _playing = false;
        _activeLanguage = null;
      });
    }
  }

  Future<void> _goTo(int index) async {
    final wasPlaying = _playing;
    await _pause();
    if (!mounted) return;
    setState(
      () => _pageIndex = index.clamp(0, widget.manifest.pages.length - 1),
    );
    if (wasPlaying) await _start();
  }

  Future<void> _changeMode(ReadingMode mode) async {
    final wasPlaying = _playing;
    await _pause();
    if (!mounted) return;
    setState(() => _mode = mode);
    if (wasPlaying) await _start();
  }

  Widget _pageImage(ManifestPageData page) {
    final uri = Uri.parse(widget.api.absoluteUrl(page.imageUrl));
    if (uri.scheme == 'file') {
      return Image.file(
        File.fromUri(uri),
        fit: BoxFit.contain,
        key: ValueKey(page.id),
      );
    }
    return Image.network(
      uri.toString(),
      headers: widget.api.authHeaders,
      fit: BoxFit.contain,
      key: ValueKey(page.id),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(
              child: CircularProgressIndicator(color: BraveColors.aurora),
            ),
    );
  }

  String _caption() => switch (_mode) {
    ReadingMode.follow => page.originalText,
    ReadingMode.chinese => page.zhText,
    ReadingMode.english => page.enText,
    ReadingMode.zhThenEn => _activeLanguage == 'en' ? page.enText : page.zhText,
    ReadingMode.enThenZh => _activeLanguage == 'zh' ? page.zhText : page.enText,
  };

  void _showModePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BraveColors.midnight,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '选择朗读方式',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ...ReadingMode.values.map(
                (mode) => ListTile(
                  textColor: Colors.white,
                  iconColor: BraveColors.aurora,
                  leading: Icon(
                    mode == _mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(
                    mode.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _changeMode(mode);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPagePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BraveColors.polar,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .48,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: .72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: widget.manifest.pages.length,
            itemBuilder: (context, index) {
              final item = widget.manifest.pages[index];
              final uri = Uri.parse(widget.api.absoluteUrl(item.thumbnailUrl));
              final image = uri.scheme == 'file'
                  ? Image.file(File.fromUri(uri), fit: BoxFit.cover)
                  : Image.network(
                      uri.toString(),
                      headers: widget.api.authHeaders,
                      fit: BoxFit.cover,
                    );
              return InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _goTo(index);
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: index == _pageIndex
                          ? BraveColors.coral
                          : Colors.transparent,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          color: BraveColors.midnight.withValues(alpha: .72),
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showHelper() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BraveColors.polar,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  SnowFoxMark(size: 50),
                  SizedBox(width: 14),
                  Text(
                    '给家长的小提示',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                page.explanation,
                style: const TextStyle(fontSize: 17, height: 1.6),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: BraveColors.ice,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '可以问孩子',
                      style: TextStyle(
                        color: BraveColors.auroraDeep,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      page.question,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '这个提示不会自动朗读，也不会打断翻页。',
                style: TextStyle(color: BraveColors.mist, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manifest.pages.isEmpty) {
      return const Scaffold(body: Center(child: Text('这本绘本还没有正文页')));
    }
    return Scaffold(
      backgroundColor: BraveColors.midnight,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.manifest.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _showHelper,
                      tooltip: '家长提示',
                      icon: const Icon(
                        Icons.lightbulb_outline_rounded,
                        color: BraveColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -200 &&
                        _pageIndex < widget.manifest.pages.length - 1) {
                      _goTo(_pageIndex + 1);
                    }
                    if ((details.primaryVelocity ?? 0) > 200 &&
                        _pageIndex > 0) {
                      _goTo(_pageIndex - 1);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(
                            begin: .985,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Container(
                        key: ValueKey(page.id),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDF8FC),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 30,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _pageImage(page),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  constraints: const BoxConstraints(maxHeight: 116),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _caption(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(
                  children: [
                    _RoundControl(
                      icon: Icons.grid_view_rounded,
                      onTap: _showPagePicker,
                      label:
                          '${_pageIndex + 1}/${widget.manifest.pages.length}',
                    ),
                    const Spacer(),
                    _RoundControl(
                      icon: Icons.skip_previous_rounded,
                      onTap: _pageIndex == 0
                          ? null
                          : () => _goTo(_pageIndex - 1),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: BraveColors.coral,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _playing ? _pause : _start,
                        child: SizedBox.square(
                          dimension: 74,
                          child: Icon(
                            _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 42,
                            color: BraveColors.midnight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _RoundControl(
                      icon: Icons.skip_next_rounded,
                      onTap: _pageIndex >= widget.manifest.pages.length - 1
                          ? null
                          : () => _goTo(_pageIndex + 1),
                    ),
                    const Spacer(),
                    _RoundControl(
                      icon: Icons.translate_rounded,
                      onTap: _showModePicker,
                      label: _mode.label,
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

class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.icon, required this.onTap, this.label});
  final IconData icon;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white.withValues(alpha: onTap == null ? .05 : .13),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 48,
              child: Icon(
                icon,
                color: onTap == null ? Colors.white24 : Colors.white,
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              label!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ),
        ],
      ],
    );
  }
}
