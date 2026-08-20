import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ai_api_health_service.dart';
import '../services/ai_usage_store.dart';
import '../theme/app_theme.dart';

class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({super.key});

  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  final _store = const AiUsageStore();
  AiUsageStats? _stats;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final stats = await _store.load();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 消耗统计',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: '刷新统计',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: stats == null
          ? const Center(child: CircularProgressIndicator())
          : _UsageBody(stats: stats),
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.stats});

  final AiUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startWeek = startToday.subtract(Duration(days: now.weekday - 1));
    final startMonth = DateTime(now.year, now.month);
    final startYear = DateTime(now.year);
    final successful = stats.events.where((event) => event.succeeded).toList();
    final operationTotals = <String, int>{};
    final modelTotals = <String, int>{};
    for (final event in successful) {
      operationTotals.update(
        event.operation,
        (value) => value + math.max(1, event.totalTokens),
        ifAbsent: () => math.max(1, event.totalTokens),
      );
      modelTotals.update(
        event.model.isEmpty ? '未知模型' : event.model,
        (value) => value + math.max(1, event.totalTokens),
        ifAbsent: () => math.max(1, event.totalTokens),
      );
    }
    final daily = List<int>.filled(7, 0);
    for (var index = 0; index < 7; index++) {
      final day = startToday.subtract(Duration(days: 6 - index));
      final next = day.add(const Duration(days: 1));
      daily[index] = successful
          .where(
            (event) =>
                !event.createdAt.isBefore(day) &&
                event.createdAt.isBefore(next),
          )
          .fold(0, (sum, event) => sum + math.max(1, event.totalTokens));
    }
    final hourly = List<int>.filled(24, 0);
    for (final event in successful.where(
      (event) => !event.createdAt.isBefore(startToday),
    )) {
      hourly[event.createdAt.hour] += math.max(1, event.totalTokens);
    }
    final balance = AiApiHealthService.instance.balance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Card(
          color: const Color(0xFFEAF7F2),
          child: ListTile(
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.teal,
            ),
            title: const Text(
              'API 实时余额',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(balance?.label ?? '正在检测供应商余额接口'),
            trailing: Text(
              balance?.displayText ?? '检测中…',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PeriodCard(label: '今天', events: _since(stats.events, startToday)),
            _PeriodCard(label: '本周', events: _since(stats.events, startWeek)),
            _PeriodCard(label: '本月', events: _since(stats.events, startMonth)),
            _PeriodCard(label: '本年', events: _since(stats.events, startYear)),
          ],
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: '最近 7 天 Token 趋势',
          subtitle: '柱形高度显示每天的消耗集中程度',
          child: _BarChart(values: daily),
        ),
        const SizedBox(height: 10),
        _ChartCard(
          title: '今天 24 小时消耗分布',
          subtitle: '可定位消耗集中在哪个时间段',
          child: _HourlyHeat(values: hourly),
        ),
        const SizedBox(height: 10),
        _BreakdownCard(title: '消耗用途', values: operationTotals),
        const SizedBox(height: 10),
        _BreakdownCard(title: '模型消耗排行', values: modelTotals),
        const SizedBox(height: 16),
        Text('逐次消耗记录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        if (stats.events.isEmpty)
          const Card(child: ListTile(title: Text('还没有 AI 调用记录')))
        else
          for (final event in stats.events.take(500))
            Card(
              child: ListTile(
                leading: Icon(
                  event.succeeded
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: event.succeeded ? AppColors.teal : Colors.red,
                ),
                title: Text('${event.operation} · ${event.model}'),
                subtitle: Text(
                  '${_dateTime(event.createdAt)} · ${(event.elapsedMs / 1000).toStringAsFixed(1)} 秒'
                  '${event.errorCategory.isEmpty ? '' : ' · ${event.errorCategory}'}',
                ),
                trailing: Text(
                  event.totalTokens > 0
                      ? '${event.totalTokens}\nToken'
                      : event.succeeded
                      ? '已完成'
                      : '失败',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
      ],
    );
  }

  static List<AiUsageEvent> _since(List<AiUsageEvent> values, DateTime start) =>
      values.where((event) => !event.createdAt.isBefore(start)).toList();

  static String _dateTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.events});
  final String label;
  final List<AiUsageEvent> events;

  @override
  Widget build(BuildContext context) {
    final tokens = events.fold<int>(0, (sum, event) => sum + event.totalTokens);
    final failures = events.where((event) => !event.succeeded).length;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 48) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted)),
              Text(
                '$tokens Token',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${events.length} 次 · $failures 次失败',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 130, child: child),
        ],
      ),
    ),
  );
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(1, math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < values.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${values[index]}', style: const TextStyle(fontSize: 9)),
                  const SizedBox(height: 3),
                  Container(
                    height: 88 * values[index] / maximum + 3,
                    decoration: BoxDecoration(
                      color: index == values.length - 1
                          ? AppColors.coral
                          : AppColors.teal,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  Text('${index - 6}天', style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HourlyHeat extends StatelessWidget {
  const _HourlyHeat({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(1, math.max);
    return Wrap(
      spacing: 4,
      runSpacing: 7,
      children: [
        for (var hour = 0; hour < 24; hour++)
          Tooltip(
            message: '$hour:00 · ${values[hour]} Token',
            child: Container(
              width: (MediaQuery.sizeOf(context).width - 88) / 8,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(
                  alpha: .12 + .78 * values[hour] / maximum,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$hour',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.title, required this.values});
  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maximum = entries.isEmpty ? 1 : entries.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            if (entries.isEmpty)
              const Text('暂无数据', style: TextStyle(color: AppColors.muted)),
            for (final entry in entries.take(8)) ...[
              Row(
                children: [
                  Expanded(child: Text(entry.key)),
                  Text('${entry.value}'),
                ],
              ),
              const SizedBox(height: 3),
              LinearProgressIndicator(
                value: entry.value / maximum,
                minHeight: 7,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
