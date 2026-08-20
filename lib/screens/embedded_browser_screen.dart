import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/app_notice_center.dart';
import '../services/secure_settings_store.dart';

String browserPageUrl(String source) {
  var value = source.trim();
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority) return value;
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path == '/v1' || path == '/api/v1') {
    return uri.replace(path: '/', query: null, fragment: null).toString();
  }
  return uri.toString();
}

class EmbeddedBrowserScreen extends StatefulWidget {
  const EmbeddedBrowserScreen({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<EmbeddedBrowserScreen> createState() => _EmbeddedBrowserScreenState();
}

class _EmbeddedBrowserScreenState extends State<EmbeddedBrowserScreen> {
  late final WebViewController _web;
  final _address = TextEditingController();
  var _loading = true;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    final initialUrl = browserPageUrl(widget.initialUrl);
    _currentUrl = initialUrl;
    _address.text = initialUrl;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _currentUrl = url;
              _address.text = url;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _currentUrl = url;
              _address.text = url;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            AppNoticeCenter.instance.showError(
              StateError('${error.errorCode} ${error.description}'),
              operation: '网页加载',
            );
          },
          onHttpError: (error) {
            final response = error.response;
            if (!mounted || response == null) return;
            final failedUri = response.uri;
            if (failedUri != null && failedUri.toString() != _currentUrl) {
              return;
            }
            AppNoticeCenter.instance.show(
              '网页返回 HTTP ${response.statusCode}：${failedUri ?? _currentUrl}\n'
              '如果这是 /v1 API 地址，请打开域名首页；API 接口本身通常没有网页。',
              kind: AppNoticeKind.error,
              duration: const Duration(seconds: 12),
            );
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                (uri.scheme != 'http' && uri.scheme != 'https')) {
              AppNoticeCenter.instance.show(
                '内置浏览器只允许打开 HTTP/HTTPS 网页。',
                kind: AppNoticeKind.warning,
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
    if (initialUrl != widget.initialUrl.trim()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppNoticeCenter.instance.show(
          '检测到 /v1 API 服务地址，已为你打开可浏览的网站首页。',
          kind: AppNoticeKind.info,
        );
      });
    }
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  String? get _host => Uri.tryParse(_currentUrl)?.host.toLowerCase();

  Future<void> _go() async {
    final original = _address.text.trim();
    final value = browserPageUrl(original);
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      AppNoticeCenter.instance.show(
        '请输入有效的 HTTP/HTTPS 网页地址。',
        kind: AppNoticeKind.error,
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (value != original) {
      _address.text = value;
      AppNoticeCenter.instance.show(
        '已将 API /v1 地址转换为网站首页。',
        kind: AppNoticeKind.info,
      );
    }
    await _web.loadRequest(uri);
  }

  Future<void> _manageCredential() async {
    final host = _host;
    if (host == null || host.isEmpty) return;
    const storage = SecureSettingsStore();
    final storageKey = 'browser_credential_$host';
    var savedUser = '';
    var savedPassword = '';
    try {
      final raw = await storage.read(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        savedUser = json['username']?.toString() ?? '';
        savedPassword = json['password']?.toString() ?? '';
      }
    } on Object {
      // A platform without secure storage can still browse without saving.
    }
    if (!mounted) return;
    final user = TextEditingController(text: savedUser);
    final password = TextEditingController(text: savedPassword);
    var obscure = true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$host · 账号保管'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '仅在你点击“保存并填写”后保存。密码进入 Android Keystore 加密存储，不会加入换机备份。请只在可信网站使用。',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: user,
                onChanged: (_) => setDialogState(() {}),
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: '账号 / 邮箱'),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: password,
                onChanged: (_) => setDialogState(() {}),
                obscureText: obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (savedUser.isNotEmpty || savedPassword.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: const Text('删除保存'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: user.text.trim().isEmpty || password.text.isEmpty
                  ? null
                  : () => Navigator.pop(context, 'save'),
              child: const Text('保存并填写'),
            ),
          ],
        ),
      ),
    );
    final username = user.text.trim();
    final secret = password.text;
    user.dispose();
    password.dispose();
    if (action == 'delete') {
      await storage.delete(storageKey);
      AppNoticeCenter.instance.show(
        '已删除 $host 保存的账号密码',
        kind: AppNoticeKind.success,
      );
      return;
    }
    if (action != 'save') return;
    try {
      await storage.write(
        storageKey,
        jsonEncode({'username': username, 'password': secret}),
      );
      await _fillCredential(username, secret);
      AppNoticeCenter.instance.show(
        '账号密码已加密保存并填写到当前页面，请自行确认后登录。',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '安全保存账号密码');
    }
  }

  Future<void> _fillCredential(String username, String password) async {
    final userJson = jsonEncode(username);
    final passwordJson = jsonEncode(password);
    await _web.runJavaScript('''
      (() => {
        const visible = (e) => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
        const password = [...document.querySelectorAll('input[type="password"]')].find(visible);
        const user = [...document.querySelectorAll('input[type="email"], input[type="text"], input:not([type])')].find(visible);
        const setValue = (e, v) => {
          if (!e) return;
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(e, v);
          e.dispatchEvent(new Event('input', {bubbles: true}));
          e.dispatchEvent(new Event('change', {bubbles: true}));
        };
        setValue(user, $userJson);
        setValue(password, $passwordJson);
      })();
    ''');
  }

  Future<void> _copyAddress() async {
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    AppNoticeCenter.instance.show('网页地址已复制', kind: AppNoticeKind.success);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 4,
      title: TextField(
        controller: _address,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _go(),
        decoration: InputDecoration(
          hintText: '输入网址',
          isDense: true,
          prefixIcon: Icon(
            _loading ? Icons.hourglass_top_rounded : Icons.lock_outline_rounded,
            size: 19,
          ),
          suffixIcon: IconButton(
            onPressed: _go,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _manageCredential,
          tooltip: '账号密码保管与一键填写',
          icon: const Icon(Icons.password_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'reload') _web.reload();
            if (value == 'copy') _copyAddress();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'reload', child: Text('刷新网页')),
            PopupMenuItem(value: 'copy', child: Text('复制地址')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _web)),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () async {
                  if (await _web.canGoBack()) await _web.goBack();
                },
                tooltip: '后退',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                onPressed: () async {
                  if (await _web.canGoForward()) await _web.goForward();
                },
                tooltip: '前进',
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              IconButton(
                onPressed: _web.reload,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                onPressed: _manageCredential,
                tooltip: '账号保管',
                icon: const Icon(Icons.shield_outlined),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
