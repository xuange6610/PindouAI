import 'package:flutter/material.dart';

import '../data/bead_palettes.dart';
import '../models/bead_palette.dart';
import '../theme/app_theme.dart';

Future<BeadPaletteId?> showPaletteSelector(
  BuildContext context, {
  required BeadPaletteId selected,
}) => showModalBottomSheet<BeadPaletteId>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _PaletteSelectorSheet(selected: selected),
);

class _PaletteSelectorSheet extends StatefulWidget {
  const _PaletteSelectorSheet({required this.selected});

  final BeadPaletteId selected;

  @override
  State<_PaletteSelectorSheet> createState() => _PaletteSelectorSheetState();
}

class _PaletteSelectorSheetState extends State<_PaletteSelectorSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final palettes = BeadPalettes.all
        .where((palette) => palette.matchesQuery(_query))
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                '选择拼豆品牌与色号系列',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '模糊搜索 MARD、漫漫、XW、Perler 等',
                ),
              ),
            ),
            Expanded(
              child: palettes.isEmpty
                  ? const Center(child: Text('没有匹配的拼豆系列'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                      itemCount: palettes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final palette = palettes[index];
                        return ListTile(
                          selected: palette.id == widget.selected,
                          leading: Icon(
                            palette.isReference
                                ? Icons.info_outline_rounded
                                : Icons.verified_outlined,
                            color: palette.isReference
                                ? AppColors.muted
                                : AppColors.teal,
                          ),
                          title: Text(
                            palette.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${palette.colors.length} 色 · ${palette.pitchMm}mm · ${palette.description}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: palette.id == widget.selected
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, palette.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
