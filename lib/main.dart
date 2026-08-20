import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'screens/home_shell.dart';
import 'services/app_settings.dart';
import 'services/app_notice_center.dart';
import 'services/ai_api_health_service.dart';
import 'services/click_sound_service.dart';
import 'services/local_music_service.dart';
import 'theme/app_theme.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppNoticeCenter.instance.showError(
          details.exception,
          operation: '界面运行',
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        AppNoticeCenter.instance.showError(error, operation: '程序运行');
        return true;
      };
      runApp(const BeadAiApp());
      // Settings are optional startup state. Never delay the first frame on a
      // desktop plugin call; defaults render immediately and saved values follow.
      unawaited(AppSettings.instance.initialize());
      unawaited(AiApiHealthService.instance.initialize());
      unawaited(LocalMusicService.instance.initialize());
    },
    (error, stack) {
      AppNoticeCenter.instance.showError(error, operation: '程序运行');
    },
  );
}

class BeadAiApp extends StatefulWidget {
  const BeadAiApp({super.key});

  @override
  State<BeadAiApp> createState() => _BeadAiAppState();
}

class _BeadAiAppState extends State<BeadAiApp> {
  Offset? _soundPointerOrigin;
  var _soundPointerMoved = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppStrings.text(context, 'appTitle'),
        debugShowCheckedModeBanner: false,
        locale: AppSettings.instance.locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.lightWith(AppSettings.instance.accent),
        builder: (context, child) => AppNoticeHost(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _soundPointerOrigin = event.position;
              _soundPointerMoved = false;
            },
            onPointerMove: (event) {
              final origin = _soundPointerOrigin;
              if (origin != null &&
                  (event.position - origin).distanceSquared > 64) {
                _soundPointerMoved = true;
              }
            },
            onPointerCancel: (_) {
              _soundPointerOrigin = null;
              _soundPointerMoved = false;
            },
            onPointerUp: (_) {
              final moved = _soundPointerMoved;
              _soundPointerOrigin = null;
              _soundPointerMoved = false;
              if (moved) return;
              if (!AppSettings.instance.soundEnabled) return;
              unawaited(
                ClickSoundService.instance.play(
                  soundId: AppSettings.instance.clickSoundId,
                ),
              );
            },
            child: child,
          ),
        ),
        home: const HomeShell(),
      ),
    );
  }
}
