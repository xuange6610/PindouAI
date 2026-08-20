import 'package:flutter/material.dart';

import '../services/project_repository.dart';

Future<String?> showFavoriteCategoryPicker(
  BuildContext context, {
  required ProjectRepository repository,
  String? currentCategory,
}) async {
  final categories = await repository.loadFavoriteCategories();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '收藏到分组',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text('选择一个分组后才会完成收藏'),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        String? errorText;
                        final value = await showDialog<String>(
                          context: context,
                          builder: (context) => StatefulBuilder(
                            builder: (context, setDialogState) => AlertDialog(
                              title: const Text('新建收藏分组'),
                              content: TextField(
                                controller: controller,
                                autofocus: true,
                                maxLength: 24,
                                decoration: InputDecoration(
                                  labelText: '分组名称',
                                  errorText: errorText,
                                ),
                                onSubmitted: (text) {
                                  final name = text.trim();
                                  if (name.isEmpty) {
                                    setDialogState(() => errorText = '请输入分组名称');
                                  } else {
                                    Navigator.pop(context, name);
                                  }
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    final name = controller.text.trim();
                                    if (name.isEmpty) {
                                      setDialogState(
                                        () => errorText = '请输入分组名称',
                                      );
                                      return;
                                    }
                                    Navigator.pop(context, name);
                                  },
                                  child: const Text('创建并选择'),
                                ),
                              ],
                            ),
                          ),
                        );
                        controller.dispose();
                        if (value == null || !sheetContext.mounted) return;
                        if (!categories.contains(value)) {
                          categories.add(value);
                          await repository.saveFavoriteCategories(categories);
                        }
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, value);
                        }
                      },
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = (currentCategory ?? '未分类') == category;
                    return ListTile(
                      leading: Icon(
                        selected ? Icons.folder_rounded : Icons.folder_outlined,
                      ),
                      title: Text(
                        category,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w600,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, category),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
