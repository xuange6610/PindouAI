import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'collection_original_service.dart';

class CollectionPatternItem {
  const CollectionPatternItem({
    required this.id,
    required this.name,
    required this.category,
    required this.width,
    required this.height,
    required this.bytes,
    required this.extension,
    this.relativePath,
    this.asset,
    this.localPath,
    this.isFavorite = false,
    this.isPinned = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String category;
  final int width;
  final int height;
  final int bytes;
  final String extension;
  final String? relativePath;
  final String? asset;
  final String? localPath;
  final bool isFavorite;
  final bool isPinned;
  final int sortOrder;

  bool get isUserUpload => localPath != null;

  CollectionPatternItem copyWith({
    String? name,
    String? category,
    bool? isFavorite,
    bool? isPinned,
    int? sortOrder,
  }) => CollectionPatternItem(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    width: width,
    height: height,
    bytes: bytes,
    extension: extension,
    relativePath: relativePath,
    asset: asset,
    localPath: localPath,
    isFavorite: isFavorite ?? this.isFavorite,
    isPinned: isPinned ?? this.isPinned,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'width': width,
    'height': height,
    'bytes': bytes,
    'extension': extension,
    'localPath': localPath,
    'isPinned': isPinned,
    'sortOrder': sortOrder,
  };

  factory CollectionPatternItem.userFromJson(Map<String, dynamic> json) =>
      CollectionPatternItem(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? '我的上传',
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        bytes: json['bytes'] as int? ?? 0,
        extension: json['extension'] as String? ?? '',
        localPath: json['localPath'] as String,
        isPinned: json['isPinned'] as bool? ?? false,
        sortOrder: json['sortOrder'] as int? ?? 0,
      );
}

class CollectionLibrary extends ChangeNotifier {
  CollectionLibrary._();

  static final CollectionLibrary instance = CollectionLibrary._();
  static const _favoritesKey = 'collection_favorite_ids';
  static const _nameOverridesKey = 'collection_name_overrides';
  static const _hiddenBuiltInIdsKey = 'collection_hidden_builtin_ids';
  static const _sourceAddressesKey = 'collection_source_addresses';
  static const _categoryOrderKey = 'collection_category_order_v2';

  final _builtIn = <CollectionPatternItem>[];
  final _uploads = <CollectionPatternItem>[];
  final _categories = <String>{};
  final _sourceAddresses = <String>[];
  final _categoryOrder = <String>[];
  Future<void>? _initializing;

  List<CollectionPatternItem> get items =>
      List.unmodifiable([..._builtIn, ..._uploads]);
  List<CollectionPatternItem> get userUploads {
    final values = [..._uploads]
      ..sort((left, right) {
        if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
        return left.sortOrder.compareTo(right.sortOrder);
      });
    return List.unmodifiable(values);
  }

  List<CollectionPatternItem> get favorites =>
      items.where((item) => item.isFavorite).toList(growable: false);
  List<String> get sourceAddresses => List.unmodifiable(_sourceAddresses);
  List<String> get userCategories {
    final values = <String>[
      for (final value in categoryOrder)
        if (_categories.contains(value)) value,
      for (final value in _categories)
        if (!_categoryOrder.contains(value)) value,
    ];
    return List.unmodifiable(values);
  }

  List<String> get categoryOrder {
    final available = <String>{
      for (final item in items) item.category,
      ..._categories,
    };
    final values = <String>[
      for (final value in _categoryOrder)
        if (available.contains(value)) value,
      for (final item in items)
        if (!_categoryOrder.contains(item.category)) item.category,
      for (final value in _categories)
        if (!_categoryOrder.contains(value)) value,
    ];
    return List.unmodifiable(values.toSet().toList());
  }

  Future<void> initialize() => _initializing ??= _load();

  Future<Directory> _uploadDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}collection_uploads',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _metadataFile() async {
    final documents = await getApplicationDocumentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}collection_uploads.json',
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteIds = (prefs.getStringList(_favoritesKey) ?? const <String>[])
        .toSet();
    final nameOverrides = _decodeStringMap(prefs.getString(_nameOverridesKey));
    final hiddenBuiltInIds =
        (prefs.getStringList(_hiddenBuiltInIdsKey) ?? const <String>[]).toSet();
    _sourceAddresses
      ..clear()
      ..addAll(prefs.getStringList(_sourceAddressesKey) ?? const <String>[]);
    _categoryOrder
      ..clear()
      ..addAll(prefs.getStringList(_categoryOrderKey) ?? const <String>[]);
    final configuredSource = AppSettings.instance.collectionBaseUrl.trim();
    if (configuredSource.isNotEmpty &&
        !_sourceAddresses.contains(configuredSource)) {
      _sourceAddresses.insert(0, configuredSource);
    }
    String manifestSource;
    try {
      manifestSource = await rootBundle.loadString(
        'assets/pindou_collection/manifest.json',
      );
    } on FlutterError {
      manifestSource = await rootBundle.loadString(
        'assets/pindou_collection/manifest.opensource.json',
      );
    }
    final manifest = jsonDecode(manifestSource) as Map<String, dynamic>;
    _builtIn.clear();
    final manifestCategories =
        (manifest['categories'] as List)
            .map((value) => (value as Map).cast<String, dynamic>())
            .toList()
          ..sort(
            (left, right) => _categorySortKey(
              left['name'] as String,
            ).compareTo(_categorySortKey(right['name'] as String)),
          );
    for (
      var categoryIndex = 0;
      categoryIndex < manifestCategories.length;
      categoryIndex++
    ) {
      final category = manifestCategories[categoryIndex];
      final categoryName = _numberedCategoryName(
        categoryIndex + 1,
        category['name'] as String,
      );
      for (final rawItem in category['items'] as List) {
        final item = (rawItem as Map).cast<String, dynamic>();
        final relativePath = item['relativePath'] as String;
        final id = 'builtin:$relativePath';
        if (hiddenBuiltInIds.contains(id)) continue;
        _builtIn.add(
          CollectionPatternItem(
            id: id,
            name: nameOverrides[id] ?? item['name'] as String,
            category: categoryName,
            relativePath: relativePath,
            asset: item['asset'] as String,
            width: item['width'] as int,
            height: item['height'] as int,
            bytes: item['bytes'] as int,
            extension: item['extension'] as String,
            isFavorite: favoriteIds.contains(id),
          ),
        );
      }
    }

    _uploads.clear();
    final metadata = await _metadataFile();
    if (await metadata.exists()) {
      try {
        final payload =
            jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
        _categories.addAll(
          (payload['categories'] as List? ?? const []).cast<String>(),
        );
        var fallbackOrder = 0;
        for (final raw in payload['items'] as List? ?? const []) {
          final item = CollectionPatternItem.userFromJson(
            (raw as Map).cast<String, dynamic>(),
          );
          if (await File(item.localPath!).exists()) {
            _uploads.add(
              item.copyWith(
                isFavorite: favoriteIds.contains(item.id),
                sortOrder: item.sortOrder == 0 ? fallbackOrder : item.sortOrder,
              ),
            );
            _categories.add(item.category);
          }
          fallbackOrder++;
        }
      } on Object catch (error) {
        debugPrint('Unable to load uploaded collection items: $error');
      }
    }
    _categories.add('我的上传');
    await _saveCategoryOrder();
    notifyListeners();
  }

  Future<void> toggleFavorite(CollectionPatternItem item) async {
    final next = !item.isFavorite;
    void update(List<CollectionPatternItem> values) {
      final index = values.indexWhere((value) => value.id == item.id);
      if (index >= 0) values[index] = values[index].copyWith(isFavorite: next);
    }

    update(_builtIn);
    update(_uploads);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((value) => value.id).toList(growable: false),
    );
  }

  Future<void> renameBuiltIn(CollectionPatternItem item, String value) async {
    if (item.isUserUpload) return;
    final name = value.trim();
    if (name.isEmpty) return;
    final index = _builtIn.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return;
    _builtIn[index] = _builtIn[index].copyWith(name: name);
    final prefs = await SharedPreferences.getInstance();
    final overrides = _decodeStringMap(prefs.getString(_nameOverridesKey));
    overrides[item.id] = name;
    await prefs.setString(_nameOverridesKey, jsonEncode(overrides));
    notifyListeners();
  }

  Future<void> deleteBuiltIn(CollectionPatternItem item) async {
    if (item.isUserUpload) return;
    final removed = _builtIn.where((entry) => entry.id == item.id).isNotEmpty;
    if (!removed) return;
    _builtIn.removeWhere((entry) => entry.id == item.id);
    final prefs = await SharedPreferences.getInstance();
    final hidden =
        (prefs.getStringList(_hiddenBuiltInIdsKey) ?? const <String>[]).toSet()
          ..add(item.id);
    await prefs.setStringList(_hiddenBuiltInIdsKey, hidden.toList()..sort());
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((value) => value.id).toList(growable: false),
    );
    notifyListeners();
  }

  Future<void> deleteItem(CollectionPatternItem item) =>
      item.isUserUpload ? deleteUpload(item) : deleteBuiltIn(item);

  /// Restores the collection presentation to its packaged first-run state.
  /// User uploads are removed only after the caller has shown a confirmation.
  Future<void> resetToDefaults() async {
    await initialize();
    for (final item in List<CollectionPatternItem>.from(_uploads)) {
      final path = item.localPath;
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final metadata = await _metadataFile();
    if (await metadata.exists()) await metadata.delete();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_favoritesKey),
      prefs.remove(_nameOverridesKey),
      prefs.remove(_hiddenBuiltInIdsKey),
      prefs.remove(_sourceAddressesKey),
      prefs.remove(_categoryOrderKey),
    ]);
    _builtIn.clear();
    _uploads.clear();
    _categories.clear();
    _sourceAddresses.clear();
    _categoryOrder.clear();
    _initializing = null;
    await initialize();
  }

  Future<void> addSourceAddress(String value, {bool activate = true}) async {
    final address = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (address.isEmpty) throw const FormatException('请输入合集地址或备注文本');
    _sourceAddresses.remove(address);
    _sourceAddresses.insert(0, address);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sourceAddressesKey, _sourceAddresses);
    final uri = Uri.tryParse(address);
    final canActivate =
        uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    if (activate && canActivate) {
      await AppSettings.instance.setCollectionBaseUrl(address);
    }
    notifyListeners();
  }

  Future<void> removeSourceAddress(String address) async {
    _sourceAddresses.remove(address);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sourceAddressesKey, _sourceAddresses);
    if (AppSettings.instance.collectionBaseUrl == address) {
      await AppSettings.instance.setCollectionBaseUrl(
        _sourceAddresses.isEmpty ? '' : _sourceAddresses.first,
      );
    }
    notifyListeners();
  }

  Future<void> activateSourceAddress(String address) async {
    if (!_sourceAddresses.contains(address)) {
      await addSourceAddress(address);
      return;
    }
    await AppSettings.instance.setCollectionBaseUrl(address);
    notifyListeners();
  }

  Future<void> testSourceAddress(String address) async {
    if (_builtIn.isEmpty) await initialize();
    final sample = _builtIn.firstWhere(
      (item) => item.relativePath != null,
      orElse: () => throw StateError('内置合集没有可测试的素材'),
    );
    final bytes = await const CollectionOriginalService().fetch(
      sample.relativePath!,
      baseUrl: address,
    );
    final decoded = await compute(_decodeDimensions, bytes);
    if (decoded == null) throw StateError('该地址返回的内容不是有效图片');
  }

  Future<void> addCategory(String value) async {
    final category = value.trim();
    if (category.isEmpty) return;
    _categories.add(category);
    if (!_categoryOrder.contains(category)) _categoryOrder.add(category);
    await _saveUploads();
    notifyListeners();
  }

  Future<void> renameCategory(String previous, String value) async {
    final next = value.trim();
    if (previous == '我的上传' || next.isEmpty || previous == next) return;
    if (_categories.contains(next)) {
      throw StateError('已存在“$next”分类');
    }
    _categories
      ..remove(previous)
      ..add(next);
    final orderIndex = _categoryOrder.indexOf(previous);
    if (orderIndex >= 0) _categoryOrder[orderIndex] = next;
    for (var index = 0; index < _uploads.length; index++) {
      if (_uploads[index].category == previous) {
        _uploads[index] = _uploads[index].copyWith(category: next);
      }
    }
    await _saveUploads();
    notifyListeners();
  }

  Future<void> deleteCategory(String category) async {
    if (category == '我的上传') return;
    if (_uploads.any((item) => item.category == category)) {
      throw StateError('分类中还有图纸，请先移动或删除这些图纸');
    }
    _categories.remove(category);
    _categoryOrder.remove(category);
    await _saveUploads();
    notifyListeners();
  }

  Future<int> importFiles(List<XFile> files, {required String category}) async {
    if (files.isEmpty) return 0;
    final directory = await _uploadDirectory();
    var imported = 0;
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        final decoded = await compute(_decodeDimensions, bytes);
        if (decoded == null) continue;
        final name = file.name.trim().isEmpty ? '我的拼豆图' : file.name;
        final extension = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : 'png';
        final id = 'user:${DateTime.now().microsecondsSinceEpoch}_$imported';
        final storageName = '${id.substring(5)}.$extension';
        final target = File(
          '${directory.path}${Platform.pathSeparator}$storageName',
        );
        await target.writeAsBytes(bytes, flush: true);
        _uploads.add(
          CollectionPatternItem(
            id: id,
            name: name,
            category: category,
            width: decoded.$1,
            height: decoded.$2,
            bytes: bytes.length,
            extension: extension,
            localPath: target.path,
            sortOrder: _uploads.length,
          ),
        );
        imported++;
      } on Object catch (error) {
        debugPrint('Unable to import ${file.name}: $error');
      }
    }
    _categories.add(category);
    await _saveUploads();
    notifyListeners();
    return imported;
  }

  Future<void> updateUpload(
    CollectionPatternItem item, {
    required String name,
    required String category,
  }) async {
    final index = _uploads.indexWhere((value) => value.id == item.id);
    if (index < 0) return;
    _uploads[index] = _uploads[index].copyWith(
      name: name.trim().isEmpty ? item.name : name.trim(),
      category: category.trim().isEmpty ? item.category : category.trim(),
    );
    _categories.add(_uploads[index].category);
    await _saveUploads();
    notifyListeners();
  }

  Future<void> togglePin(CollectionPatternItem item) async {
    final index = _uploads.indexWhere((value) => value.id == item.id);
    if (index < 0) return;
    _uploads[index] = _uploads[index].copyWith(isPinned: !item.isPinned);
    await _saveUploads();
    notifyListeners();
  }

  Future<void> reorderUploads(List<String> orderedIds) async {
    final positions = <String, int>{
      for (var index = 0; index < orderedIds.length; index++)
        orderedIds[index]: index,
    };
    for (var index = 0; index < _uploads.length; index++) {
      final item = _uploads[index];
      _uploads[index] = item.copyWith(
        sortOrder: positions[item.id] ?? orderedIds.length + index,
      );
    }
    await _saveUploads();
    notifyListeners();
  }

  Future<void> reorderCategories(List<String> orderedCategories) async {
    final current = categoryOrder;
    final unique = <String>[
      for (final value in orderedCategories)
        if (current.contains(value)) value,
      for (final value in current)
        if (!orderedCategories.contains(value)) value,
    ];
    _categoryOrder
      ..clear()
      ..addAll(unique);
    await _saveCategoryOrder();
    notifyListeners();
  }

  Future<void> moveCategoryToFront(String category) async {
    final values = categoryOrder.toList()..remove(category);
    values.insert(0, category);
    await reorderCategories(values);
  }

  Future<void> moveCategoryToBack(String category) async {
    final values = categoryOrder.toList()..remove(category);
    values.add(category);
    await reorderCategories(values);
  }

  Future<void> deleteUpload(CollectionPatternItem item) async {
    if (!item.isUserUpload) return;
    _uploads.removeWhere((value) => value.id == item.id);
    final file = File(item.localPath!);
    if (await file.exists()) await file.delete();
    await _saveUploads();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((value) => value.id).toList(growable: false),
    );
    notifyListeners();
  }

  Future<Uint8List> readOriginal(CollectionPatternItem item) async {
    if (item.localPath != null) return File(item.localPath!).readAsBytes();
    return const CollectionOriginalService().fetch(item.relativePath!);
  }

  Future<Uint8List> readPreview(CollectionPatternItem item) async {
    if (item.localPath != null) return File(item.localPath!).readAsBytes();
    final data = await rootBundle.load(item.asset!);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _saveUploads() async {
    final metadata = await _metadataFile();
    await metadata.writeAsString(
      jsonEncode({
        'version': 1,
        'categories': userCategories,
        'items': _uploads.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
  }

  Future<void> _saveCategoryOrder() async {
    final normalized = categoryOrder;
    _categoryOrder
      ..clear()
      ..addAll(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoryOrderKey, _categoryOrder);
  }
}

int _categorySortKey(String value) {
  final match = RegExp(r'^\s*(\d+)').firstMatch(value);
  return int.tryParse(match?.group(1) ?? '') ?? 100000;
}

String _numberedCategoryName(int index, String value) {
  final cleaned = value.replaceFirst(RegExp(r'^\s*\d+[.、\-\s]*'), '').trim();
  return '$index. ${cleaned.isEmpty ? value.trim() : cleaned}';
}

Map<String, String> _decodeStringMap(String? source) {
  if (source == null || source.isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  } on Object {
    return <String, String>{};
  }
}

(int, int)? _decodeDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (decoded.width, decoded.height);
}
