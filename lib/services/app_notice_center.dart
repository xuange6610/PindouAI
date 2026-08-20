import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error.dart';

enum AppNoticeKind { info, success, warning, error }

class AppNotice {
  const AppNotice({
    required this.id,
    required this.message,
    required this.kind,
    this.actionLabel,
    this.onAction,
  });

  final int id;
  final String message;
  final AppNoticeKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class AppNoticeCenter extends ChangeNotifier {
  AppNoticeCenter._();

  static final instance = AppNoticeCenter._();
  AppNotice? _notice;
  Timer? _timer;
  var _hostCount = 0;

  AppNotice? get notice => _notice;

  void show(
    String message, {
    AppNoticeKind kind = AppNoticeKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    _timer?.cancel();
    _notice = AppNotice(
      id: DateTime.now().microsecondsSinceEpoch,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    notifyListeners();
    if (_hostCount > 0) _timer = Timer(duration, dismiss);
  }

  /// Keeps legacy prompt call sites while rendering them through the global
  /// top notice host, so messages never cover controls at the bottom.
  void showSnackBar(SnackBar snackBar) {
    final content = snackBar.content;
    final message = switch (content) {
      Text(:final data, :final textSpan) =>
        data ?? textSpan?.toPlainText() ?? '操作已完成',
      _ => '操作已完成',
    };
    final normalized = message.toLowerCase();
    final kind =
        normalized.contains('失败') ||
            normalized.contains('错误') ||
            normalized.contains('异常') ||
            normalized.contains('损坏') ||
            normalized.contains('不存在') ||
            normalized.contains('无法')
        ? AppNoticeKind.error
        : normalized.contains('请先') ||
              normalized.contains('请稍候') ||
              normalized.contains('未连接') ||
              normalized.contains('没有可')
        ? AppNoticeKind.warning
        : normalized.contains('成功') ||
              normalized.contains('已保存') ||
              normalized.contains('已导入') ||
              normalized.contains('已恢复') ||
              normalized.contains('已完成') ||
              normalized.contains('已添加')
        ? AppNoticeKind.success
        : AppNoticeKind.info;
    if (kind == AppNoticeKind.error) {
      final info = AppErrorClassifier.classify(message);
      show(
        info.displayText,
        kind: kind,
        actionLabel: snackBar.action?.label,
        onAction: snackBar.action?.onPressed,
        duration: const Duration(seconds: 12),
      );
    } else {
      show(
        message,
        kind: kind,
        actionLabel: snackBar.action?.label,
        onAction: snackBar.action?.onPressed,
        duration: snackBar.duration,
      );
    }
  }

  void _attachHost() => _hostCount++;

  void _detachHost() {
    _hostCount = (_hostCount - 1).clamp(0, 1 << 20);
    if (_hostCount == 0) _timer?.cancel();
  }

  AppErrorInfo showError(
    Object error, {
    String? operation,
    VoidCallback? openApiSettings,
  }) {
    final info = AppErrorClassifier.classify(error, operation: operation);
    show(
      info.displayText,
      kind: AppNoticeKind.error,
      actionLabel: info.canOpenApiSettings && openApiSettings != null
          ? '检查 API'
          : null,
      onAction: info.canOpenApiSettings ? openApiSettings : null,
      duration: const Duration(seconds: 12),
    );
    return info;
  }

  void dismiss() {
    _timer?.cancel();
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }
}

class AppNoticeHost extends StatefulWidget {
  const AppNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppNoticeHost> createState() => _AppNoticeHostState();
}

class _AppNoticeHostState extends State<AppNoticeHost> {
  @override
  void initState() {
    super.initState();
    AppNoticeCenter.instance._attachHost();
  }

  @override
  void dispose() {
    AppNoticeCenter.instance._detachHost();
    super.dispose();
  }

  Future<void> _showNoticeDetails(AppNotice notice) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(notice.kind == AppNoticeKind.error ? '完整错误提示' : '完整提示'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(child: SelectableText(notice.message)),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('copyNoticeDetails'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: notice.message));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              AppNoticeCenter.instance.show(
                '完整提示已复制到剪贴板',
                kind: AppNoticeKind.success,
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制完整提示'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      AnimatedBuilder(
        animation: AppNoticeCenter.instance,
        builder: (context, _) {
          final notice = AppNoticeCenter.instance.notice;
          if (notice == null) return const SizedBox.shrink();
          final colors = switch (notice.kind) {
            AppNoticeKind.error => (const Color(0xFFB3261E), Colors.white),
            AppNoticeKind.warning => (
              const Color(0xFFFFE0A3),
              const Color(0xFF5F4100),
            ),
            AppNoticeKind.success => (
              const Color(0xFFD8F5E5),
              const Color(0xFF135C35),
            ),
            AppNoticeKind.info => (
              const Color(0xFFDDEBFF),
              const Color(0xFF164778),
            ),
          };
          final hasDetails =
              notice.message.length > 72 || notice.message.contains('\n');
          return Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Material(
                  color: colors.$1,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Icon(
                            notice.kind == AppNoticeKind.error
                                ? Icons.error_outline_rounded
                                : Icons.info_outline_rounded,
                            color: colors.$2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notice.message,
                                maxLines: hasDetails ? 4 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.$2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (hasDetails || notice.actionLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Wrap(
                                    spacing: 2,
                                    runSpacing: 0,
                                    children: [
                                      if (hasDetails)
                                        TextButton.icon(
                                          key: const ValueKey(
                                            'noticeDetailsButton',
                                          ),
                                          onPressed: () =>
                                              _showNoticeDetails(notice),
                                          style: TextButton.styleFrom(
                                            foregroundColor: colors.$2,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.open_in_full_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('查看完整提示'),
                                        ),
                                      if (notice.actionLabel != null)
                                        TextButton(
                                          onPressed: () {
                                            AppNoticeCenter.instance.dismiss();
                                            notice.onAction?.call();
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor: colors.$2,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          child: Text(notice.actionLabel!),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: AppNoticeCenter.instance.dismiss,
                          color: colors.$2,
                          tooltip: '关闭提示',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
