import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_clipboard_import.dart';
import '../services/api_profile_store.dart';
import '../services/app_notice_center.dart';
import '../services/app_settings.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import 'embedded_browser_screen.dart';

class ApiManagementScreen extends StatefulWidget {
  const ApiManagementScreen({super.key, this.store});

  final ApiProfileStore? store;

  @override
  State<ApiManagementScreen> createState() => _ApiManagementScreenState();
}

class _ApiManagementScreenState extends State<ApiManagementScreen> {
  late final ApiProfileStore _store;
  var _loading = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? ApiProfileStore.instance;
    _store.addListener(_changed);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      await _store.initialize();
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '读取 API 配置');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: 'API 配置管理');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCurrent() async {
    final controller = TextEditingController(text: '当前 API 配置');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存当前配置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '配置名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _run(() async {
      final profile = await _store.saveCurrent(name: name);
      await _store.activate(profile);
      AppNoticeCenter.instance.show(
        '已保存并设为当前 API：${profile.name}',
        kind: AppNoticeKind.success,
      );
    });
  }

  Future<void> _copyCurrentForShare() async {
    await _store.initialize();
    final profile = _store.currentAsProfile(name: '当前 API 配置');
    await Clipboard.setData(ClipboardData(text: _store.shareText(profile)));
    if (!mounted) return;
    AppNoticeCenter.instance.show(
      '当前完整 API 配置已复制到剪贴板，可直接分享并由对方一键识别导入。',
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _share(ApiProfile profile) async {
    await Clipboard.setData(ClipboardData(text: _store.shareText(profile)));
    if (!mounted) return;
    AppNoticeCenter.instance.show(
      '“${profile.name}”的完整配置已复制到剪贴板。内容包含 API 密钥，请只分享给可信的人。',
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _openProviderWebsite(ApiProfile profile) async {
    final source = profile.providerBaseUrl.trim().isNotEmpty
        ? profile.providerBaseUrl.trim()
        : profile.appServerBaseUrl.trim();
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      AppNoticeCenter.instance.show(
        '这个配置没有可打开的 HTTP/HTTPS 中转地址。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmbeddedBrowserScreen(initialUrl: uri.toString()),
      ),
    );
  }

  Future<void> _importClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final data = ApiClipboardImportParser.parse(text);
    if (!data.hasValues) {
      AppNoticeCenter.instance.show(
        '剪贴板中没有识别到 API 密钥、地址或模型。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final settings = AppSettings.instance;
    final provider = AppSettings.normalizeAiProviderBaseUrl(
      data.providerBaseUrl ?? settings.aiProviderBaseUrl,
    );
    final collection = AppSettings.normalizeAiProviderBaseUrl(
      data.collectionBaseUrl ??
          data.providerBaseUrl ??
          settings.collectionBaseUrl,
    );
    final host = Uri.tryParse(provider)?.host ?? '';
    final draft = ApiProfile(
      id: '',
      name: data.profileName?.trim().isNotEmpty == true
          ? data.profileName!.trim()
          : host.isEmpty
          ? '剪贴板 API'
          : host,
      appServerBaseUrl: data.appServerBaseUrl ?? settings.aiProxyBaseUrl,
      providerBaseUrl: provider,
      apiKey: data.apiKey ?? settings.aiProviderKey,
      collectionBaseUrl: collection,
      model: AppSettings.normalizeAiModelId(data.model ?? settings.aiChatModel),
      protocol: data.protocol ?? settings.aiProviderProtocol,
      updatedAt: DateTime.now(),
    );
    await _edit(draft, title: '导入剪贴板 API', activateByDefault: true);
  }

  Future<void> _edit(
    ApiProfile profile, {
    String title = '编辑 API 配置',
    bool activateByDefault = false,
  }) async {
    final name = TextEditingController(text: profile.name);
    final appServer = TextEditingController(text: profile.appServerBaseUrl);
    final provider = TextEditingController(text: profile.providerBaseUrl);
    final key = TextEditingController(text: profile.apiKey);
    final collection = TextEditingController(text: profile.collectionBaseUrl);
    final model = TextEditingController(text: profile.model);
    var protocol = profile.protocol;
    var activate = activateByDefault;
    var obscure = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: '配置名称'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: appServer,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'APP 服务端地址（可选）',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: provider,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'API 中转地址'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: key,
                    obscureText: obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'API 密钥',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                        tooltip: obscure ? '显示密钥' : '隐藏密钥',
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: collection,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: '原图库服务地址'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(
                      labelText: '对话 / 图片 / 视频模型',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AiProviderProtocol>(
                    initialValue: protocol,
                    decoration: const InputDecoration(labelText: 'API 协议'),
                    items: [
                      for (final value in AiProviderProtocol.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) protocol = value;
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: activate,
                    onChanged: (value) =>
                        setDialogState(() => activate = value ?? false),
                    title: const Text('保存后立即切换为这个 API'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await _run(() async {
        final saved = profile.copyWith(
          name: name.text,
          appServerBaseUrl: appServer.text,
          providerBaseUrl: provider.text,
          apiKey: key.text,
          collectionBaseUrl: collection.text,
          model: model.text,
          protocol: protocol,
        );
        final stored = await _store.save(saved);
        if (activate) await _store.activate(stored);
        AppNoticeCenter.instance.show(
          activate ? 'API 配置已保存并切换' : 'API 配置已保存',
          kind: AppNoticeKind.success,
        );
      });
    }
    name.dispose();
    appServer.dispose();
    provider.dispose();
    key.dispose();
    collection.dispose();
    model.dispose();
  }

  Future<void> _activate(ApiProfile profile) => _run(() async {
    await _store.activate(profile);
    AppNoticeCenter.instance.show(
      '已切换到：${profile.name}',
      kind: AppNoticeKind.success,
    );
  });

  Future<void> _delete(ApiProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 API 配置？'),
        content: Text('将删除“${profile.name}”及其安全存储中的密钥，不影响当前已加载的 API。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(() => _store.delete(profile.id));
  }

  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '拼豆 AI API 配置',
          extensions: ['json', 'beadapi'],
          mimeTypes: ['application/json'],
        ),
      ],
      confirmButtonText: '导入',
    );
    if (file == null) return;
    await _run(() async {
      final count = await _store.importBundle(await file.readAsBytes());
      AppNoticeCenter.instance.show(
        '已导入 $count 个 API 配置',
        kind: AppNoticeKind.success,
      );
    });
  }

  Future<void> _export({Iterable<String>? ids}) async {
    final count = ids?.length ?? _store.profiles.length;
    if (count == 0) {
      AppNoticeCenter.instance.show(
        '还没有可导出的 API 配置。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.security_rounded),
        title: Text('导出 $count 个 API 配置？'),
        content: const Text('导出文件会包含完整 API 密钥，便于换机导入。请保存到可信位置，不要发送给不信任的人。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择导出位置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await ExportService().saveDocumentBytesAs(
        _store.exportBundle(ids: ids),
        '拼豆AI_API配置_$stamp.beadapi.json',
        mimeType: 'application/json',
      );
      if (path != null) {
        AppNoticeCenter.instance.show(
          'API 配置已导出：$path',
          kind: AppNoticeKind.success,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text(
          'API 管理',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            key: const ValueKey('importApiProfilesFileButton'),
            onPressed: _busy ? null : _importFile,
            tooltip: '从文件导入',
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            key: const ValueKey('exportApiProfilesButton'),
            onPressed: _busy ? null : _export,
            tooltip: '导出全部',
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('manageImportApiClipboardButton'),
                        onPressed: _busy ? null : _importClipboard,
                        icon: const Icon(Icons.content_paste_go_rounded),
                        label: const Text('读取剪贴板，一键导入并设置'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('saveCurrentApiProfileButton'),
                        onPressed: _busy ? null : _saveCurrent,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('把当前 API 保存到管理列表'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey(
                          'copyCurrentApiConfigurationButton',
                        ),
                        onPressed: _busy ? null : _copyCurrentForShare,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('一键复制当前完整配置用于分享'),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '单击配置可一键切换，双击直接打开中转网页；右侧菜单支持编辑、分享、导出和删除。密钥在列表中始终隐藏。',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _store.profiles.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.dns_outlined,
                                size: 52,
                                color: AppColors.muted,
                              ),
                              SizedBox(height: 10),
                              Text('还没有保存的 API 配置'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                          itemCount: _store.profiles.length,
                          itemBuilder: (context, index) {
                            final profile = _store.profiles[index];
                            final active = profile.id == _store.activeProfileId;
                            return Card(
                              child: InkWell(
                                key: ValueKey('apiProfile_${profile.id}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: _busy ? null : () => _activate(profile),
                                onDoubleTap: _busy
                                    ? null
                                    : () => _openProviderWebsite(profile),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Icon(
                                      active
                                          ? Icons.check_rounded
                                          : Icons.cloud_outlined,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          profile.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      if (active)
                                        const Text(
                                          '当前',
                                          style: TextStyle(
                                            color: AppColors.teal,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${profile.providerBaseUrl}\n'
                                    '${profile.model} · ${_maskedKey(profile.apiKey)}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'activate') {
                                        _activate(profile);
                                      }
                                      if (value == 'edit') _edit(profile);
                                      if (value == 'open') {
                                        _openProviderWebsite(profile);
                                      }
                                      if (value == 'share') _share(profile);
                                      if (value == 'export') {
                                        _export(ids: [profile.id]);
                                      }
                                      if (value == 'delete') _delete(profile);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'activate',
                                        child: Text('切换并设为当前'),
                                      ),
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('编辑配置'),
                                      ),
                                      PopupMenuItem(
                                        value: 'open',
                                        child: Text('打开中转网页'),
                                      ),
                                      PopupMenuItem(
                                        value: 'share',
                                        child: Text('分享（复制完整配置）'),
                                      ),
                                      PopupMenuItem(
                                        value: 'export',
                                        child: Text('单独导出'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    ),
  );

  static String _maskedKey(String value) {
    if (value.isEmpty) return '未填写密钥';
    if (value.length <= 8) return '••••••••';
    return '${value.substring(0, 4)}••••${value.substring(value.length - 4)}';
  }
}
