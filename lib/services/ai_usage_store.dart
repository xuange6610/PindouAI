import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiUsageEvent {
  const AiUsageEvent({
    required this.id,
    required this.createdAt,
    required this.model,
    required this.operation,
    required this.succeeded,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.elapsedMs,
    this.errorCategory = '',
    this.estimatedCost = 0,
  });

  final String id;
  final DateTime createdAt;
  final String model;
  final String operation;
  final bool succeeded;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int elapsedMs;
  final String errorCategory;
  final double estimatedCost;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'model': model,
    'operation': operation,
    'succeeded': succeeded,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
    'elapsedMs': elapsedMs,
    if (errorCategory.isNotEmpty) 'errorCategory': errorCategory,
    if (estimatedCost > 0) 'estimatedCost': estimatedCost,
  };

  factory AiUsageEvent.fromJson(Map<String, dynamic> json) => AiUsageEvent(
    id: json['id']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    model: json['model']?.toString() ?? '',
    operation: json['operation']?.toString() ?? '聊天',
    succeeded: json['succeeded'] as bool? ?? true,
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
    elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    errorCategory: json['errorCategory']?.toString() ?? '',
    estimatedCost: (json['estimatedCost'] as num?)?.toDouble() ?? 0,
  );
}

class AiModelUsageSummary {
  const AiModelUsageSummary({
    required this.requests,
    required this.failures,
    required this.averageElapsedMs,
  });

  final int requests;
  final int failures;
  final int averageElapsedMs;

  double get failureRate => requests == 0 ? 0 : failures / requests;
}

class AiUsageStats {
  const AiUsageStats({
    this.requestCount = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.totalElapsedMs = 0,
    this.lastModel = '',
    this.events = const [],
  });

  final int requestCount;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int totalElapsedMs;
  final String lastModel;
  final List<AiUsageEvent> events;

  Map<String, AiModelUsageSummary> get modelSummaries {
    final grouped = <String, List<AiUsageEvent>>{};
    for (final event in events) {
      if (event.model.trim().isEmpty) continue;
      grouped.putIfAbsent(event.model, () => []).add(event);
    }
    return grouped.map((model, values) {
      final elapsed = values
          .where((event) => event.succeeded && event.elapsedMs > 0)
          .map((event) => event.elapsedMs)
          .toList();
      return MapEntry(
        model,
        AiModelUsageSummary(
          requests: values.length,
          failures: values.where((event) => !event.succeeded).length,
          averageElapsedMs: elapsed.isEmpty
              ? 0
              : elapsed.reduce((a, b) => a + b) ~/ elapsed.length,
        ),
      );
    });
  }
}

class AiUsageStore {
  const AiUsageStore();

  static const _requestKey = 'ai_usage_request_count';
  static const _inputKey = 'ai_usage_input_tokens';
  static const _outputKey = 'ai_usage_output_tokens';
  static const _totalKey = 'ai_usage_total_tokens';
  static const _elapsedKey = 'ai_usage_elapsed_ms';
  static const _modelKey = 'ai_usage_last_model';
  static const _eventsKey = 'ai_usage_events_v2';
  static const _maximumEvents = 5000;
  static Future<void> _writeQueue = Future.value();

  Future<AiUsageStats> load() async {
    await _writeQueue;
    final prefs = await SharedPreferences.getInstance();
    return _loadFrom(prefs);
  }

  AiUsageStats _loadFrom(SharedPreferences prefs) {
    var events = <AiUsageEvent>[];
    try {
      final decoded = jsonDecode(prefs.getString(_eventsKey) ?? '[]') as List;
      events =
          decoded
              .whereType<Map>()
              .map(
                (value) => AiUsageEvent.fromJson(value.cast<String, dynamic>()),
              )
              .where((event) => event.id.isNotEmpty)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on Object {
      events = [];
    }
    return AiUsageStats(
      requestCount: prefs.getInt(_requestKey) ?? 0,
      inputTokens: prefs.getInt(_inputKey) ?? 0,
      outputTokens: prefs.getInt(_outputKey) ?? 0,
      totalTokens: prefs.getInt(_totalKey) ?? 0,
      totalElapsedMs: prefs.getInt(_elapsedKey) ?? 0,
      lastModel: prefs.getString(_modelKey) ?? '',
      events: List.unmodifiable(events),
    );
  }

  Future<AiUsageStats> record({
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required int elapsedMs,
    String operation = 'AI 聊天',
    double estimatedCost = 0,
  }) => _append(
    model: model,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    totalTokens: totalTokens,
    elapsedMs: elapsedMs,
    operation: operation,
    succeeded: true,
    estimatedCost: estimatedCost,
  );

  Future<AiUsageStats> recordFailure({
    required String model,
    required int elapsedMs,
    required String operation,
    required String errorCategory,
  }) => _append(
    model: model,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    elapsedMs: elapsedMs,
    operation: operation,
    succeeded: false,
    errorCategory: errorCategory,
  );

  Future<AiUsageStats> _append({
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required int elapsedMs,
    required String operation,
    required bool succeeded,
    String errorCategory = '',
    double estimatedCost = 0,
  }) async {
    late AiUsageStats result;
    _writeQueue = _writeQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final current = _loadFrom(prefs);
      final event = AiUsageEvent(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        model: model,
        operation: operation,
        succeeded: succeeded,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        elapsedMs: elapsedMs,
        errorCategory: errorCategory,
        estimatedCost: estimatedCost,
      );
      final events = [event, ...current.events].take(_maximumEvents).toList();
      result = AiUsageStats(
        requestCount: current.requestCount + 1,
        inputTokens: current.inputTokens + inputTokens,
        outputTokens: current.outputTokens + outputTokens,
        totalTokens: current.totalTokens + totalTokens,
        totalElapsedMs: current.totalElapsedMs + elapsedMs,
        lastModel: model,
        events: List.unmodifiable(events),
      );
      await Future.wait([
        prefs.setInt(_requestKey, result.requestCount),
        prefs.setInt(_inputKey, result.inputTokens),
        prefs.setInt(_outputKey, result.outputTokens),
        prefs.setInt(_totalKey, result.totalTokens),
        prefs.setInt(_elapsedKey, result.totalElapsedMs),
        prefs.setString(_modelKey, result.lastModel),
        prefs.setString(
          _eventsKey,
          jsonEncode(events.map((event) => event.toJson()).toList()),
        ),
      ]);
    });
    await _writeQueue;
    return result;
  }

  Future<void> clear() async {
    _writeQueue = _writeQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_requestKey),
        prefs.remove(_inputKey),
        prefs.remove(_outputKey),
        prefs.remove(_totalKey),
        prefs.remove(_elapsedKey),
        prefs.remove(_modelKey),
        prefs.remove(_eventsKey),
      ]);
    });
    await _writeQueue;
  }
}
