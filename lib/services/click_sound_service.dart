import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ClickSoundOption {
  const ClickSoundOption(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

class ClickSoundService {
  ClickSoundService._();

  static final ClickSoundService instance = ClickSoundService._();

  static const defaultSoundId = 'rounded';
  static const options = <ClickSoundOption>[
    ClickSoundOption('rounded', '圆润', '柔和、短促的默认点击声'),
    ClickSoundOption('classic', '经典', '传统系统按钮的清晰反馈'),
    ClickSoundOption('soft', '轻柔', '低音量、低频的安静反馈'),
    ClickSoundOption('bubble', '气泡', '轻快上扬的气泡声'),
    ClickSoundOption('wood', '木鱼', '温暖短促的木质敲击声'),
    ClickSoundOption('glass', '玻璃', '通透的玻璃轻碰声'),
    ClickSoundOption('mechanical', '机械', '实体按键般的机械触感'),
    ClickSoundOption('digital', '数码', '复古电子设备提示声'),
    ClickSoundOption('bell', '铃铛', '带短尾音的明亮铃声'),
    ClickSoundOption('snap', '清脆弹响', '利落有弹性的确认声'),
  ];

  final Map<String, Uint8List> _sounds = {};
  final Map<String, Future<AudioPool>> _pools = {};
  DateTime _lastPlay = DateTime.fromMillisecondsSinceEpoch(0);
  var _commandInFlight = false;

  static bool supports(String id) => options.any((value) => value.id == id);

  static ClickSoundOption optionFor(String id) => options.firstWhere(
    (value) => value.id == id,
    orElse: () => options.first,
  );

  Future<void> play({String? soundId, bool force = false}) async {
    final now = DateTime.now();
    if (_commandInFlight) return;
    if (!force && now.difference(_lastPlay).inMilliseconds < 90) return;
    _lastPlay = now;
    final id = supports(soundId ?? '') ? soundId! : defaultSoundId;
    _commandInFlight = true;
    try {
      final pool = await _poolFor(id);
      final stop = await pool.start(volume: 0.28);
      final duration = optionFor(id).id == 'bell'
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 145);
      Timer(duration, () => unawaited(stop()));
    } on Object {
      // Keep a platform fallback for devices without a supported audio backend.
      await SystemSound.play(SystemSoundType.click);
    } finally {
      _commandInFlight = false;
    }
  }

  /// Warms one low-latency player without blocking the settings or UI thread.
  Future<void> preload([String soundId = defaultSoundId]) async {
    final id = supports(soundId) ? soundId : defaultSoundId;
    try {
      await _poolFor(id);
    } on Object {
      // Playback will use the platform click fallback if preloading is not
      // supported by this device.
    }
  }

  Future<AudioPool> _poolFor(String id) => _pools.putIfAbsent(id, () async {
    final sound = _sounds.putIfAbsent(id, () => buildSoundBytes(id));
    return AudioPool.create(
      source: BytesSource(sound, mimeType: 'audio/wav'),
      minPlayers: 1,
      maxPlayers: 2,
      playerMode: PlayerMode.lowLatency,
    );
  });

  /// Exposed for deterministic unit validation; generated sounds require no
  /// binary assets and keep the APK compact.
  Uint8List buildSoundBytes(String soundId) {
    final id = supports(soundId) ? soundId : defaultSoundId;
    const sampleRate = 22050;
    final duration = switch (id) {
      'soft' => 0.075,
      'glass' => 0.11,
      'bell' => 0.14,
      _ => 0.06,
    };
    final sampleCount = (sampleRate * duration).round();
    final bytes = Uint8List(44 + sampleCount * 2);
    final data = ByteData.sublistView(bytes);

    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        data.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + sampleCount * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, sampleCount * 2, Endian.little);

    for (var index = 0; index < sampleCount; index++) {
      final t = index / sampleRate;
      final attack = math.min(1.0, t / 0.004);
      final noise =
          ((((index * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff) * 2) - 1;
      late final double tone;
      late final double release;
      late final double gain;
      switch (id) {
        case 'classic':
          tone =
              math.sin(2 * math.pi * 980 * t) * .72 +
              math.sin(2 * math.pi * 1470 * t) * .28;
          release = math.exp(-t * 62);
          gain = 8300;
          break;
        case 'soft':
          tone =
              math.sin(2 * math.pi * 480 * t) * .86 +
              math.sin(2 * math.pi * 720 * t) * .14;
          release = math.exp(-t * 42);
          gain = 5200;
          break;
        case 'bubble':
          final phase = 2 * math.pi * (410 * t + 7200 * t * t);
          tone = math.sin(phase) * .82 + math.sin(phase * 1.48) * .18;
          release = math.exp(-t * 48);
          gain = 7800;
          break;
        case 'wood':
          tone =
              math.sin(2 * math.pi * 260 * t) * .68 +
              math.sin(2 * math.pi * 510 * t) * .2 +
              noise * .12;
          release = math.exp(-t * 74);
          gain = 9000;
          break;
        case 'glass':
          tone =
              math.sin(2 * math.pi * 1760 * t) * .56 +
              math.sin(2 * math.pi * 2637 * t) * .3 +
              math.sin(2 * math.pi * 3440 * t) * .14;
          release = math.exp(-t * 30);
          gain = 7200;
          break;
        case 'mechanical':
          tone =
              (math.sin(2 * math.pi * 620 * t) >= 0 ? .62 : -.62) + noise * .38;
          release = math.exp(-t * 95);
          gain = 7200;
          break;
        case 'digital':
          final frequency = index < sampleCount ~/ 2 ? 880.0 : 1320.0;
          tone =
              math.sin(2 * math.pi * frequency * t) * .78 +
              math.sin(2 * math.pi * frequency * 2 * t) * .22;
          release = math.exp(-t * 36);
          gain = 6800;
          break;
        case 'bell':
          tone =
              math.sin(2 * math.pi * 1180 * t) * .54 +
              math.sin(2 * math.pi * 2360 * t) * .3 +
              math.sin(2 * math.pi * 3545 * t) * .16;
          release = math.exp(-t * 22);
          gain = 7000;
          break;
        case 'snap':
          tone =
              math.sin(2 * math.pi * (1250 - 5200 * t) * t) * .64 + noise * .36;
          release = math.exp(-t * 88);
          gain = 9000;
          break;
        case 'rounded':
        default:
          final frequency = 820 + 260 * math.exp(-t * 34);
          tone =
              math.sin(2 * math.pi * frequency * t) * .78 +
              math.sin(2 * math.pi * (frequency * 1.52) * t) * .22;
          release = math.exp(-t * 68);
          gain = 8200;
          break;
      }
      final sample = (tone * attack * release * gain).round().clamp(
        -32768,
        32767,
      );
      data.setInt16(44 + index * 2, sample, Endian.little);
    }
    return bytes;
  }
}
