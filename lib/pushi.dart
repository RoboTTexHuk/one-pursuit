import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as NcupMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as NcupTimezoneData;
import 'package:timezone/timezone.dart' as NcupTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// NCUP инфраструктура (бывшая Dress Retro инфраструктура)
// ============================================================================

class NcupLogger {
  const NcupLogger();

  void NcupLogInfo(Object NcupMessage) =>
      debugPrint('[DressRetroLogger] $NcupMessage');

  void NcupLogWarn(Object NcupMessage) =>
      debugPrint('[DressRetroLogger/WARN] $NcupMessage');

  void NcupLogError(Object NcupMessage) =>
      debugPrint('[DressRetroLogger/ERR] $NcupMessage');
}

class NcupVault {
  static final NcupVault SharedInstance = NcupVault._InternalConstructor();
  NcupVault._InternalConstructor();
  factory NcupVault() => SharedInstance;

  final NcupLogger NcupLoggerInstance = const NcupLogger();
}

// ============================================================================
// Константы (статистика/кеш) — строки в кавычках не меняем
// ============================================================================

const String MetrLoadedOnceKey = 'wheel_loaded_once';
const String MetrStatEndpoint = 'https://getgame.portalroullete.bar/stat';
const String MetrCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Утилиты: NcupKit (бывший DressRetroKit)
// ============================================================================

class NcupKit {
  static bool NcupLooksLikeBareMail(Uri NcupUri) {
    final String NcupScheme = NcupUri.scheme;
    if (NcupScheme.isNotEmpty) return false;
    final String NcupRaw = NcupUri.toString();
    return NcupRaw.contains('@') && !NcupRaw.contains(' ');
  }

  static Uri NcupToMailto(Uri NcupUri) {
    final String NcupFull = NcupUri.toString();
    final List<String> NcupBits = NcupFull.split('?');
    final String NcupWho = NcupBits.first;
    final Map<String, String> NcupQuery =
    NcupBits.length > 1 ? Uri.splitQueryString(NcupBits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: NcupWho,
      queryParameters: NcupQuery.isEmpty ? null : NcupQuery,
    );
  }

  static Uri NcupGmailize(Uri NcupMailUri) {
    final Map<String, String> NcupQp = NcupMailUri.queryParameters;
    final Map<String, String> NcupParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (NcupMailUri.path.isNotEmpty) 'to': NcupMailUri.path,
      if ((NcupQp['subject'] ?? '').isNotEmpty) 'su': NcupQp['subject']!,
      if ((NcupQp['body'] ?? '').isNotEmpty) 'body': NcupQp['body']!,
      if ((NcupQp['cc'] ?? '').isNotEmpty) 'cc': NcupQp['cc']!,
      if ((NcupQp['bcc'] ?? '').isNotEmpty) 'bcc': NcupQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', NcupParams);
  }

  static String NcupDigitsOnly(String NcupSource) =>
      NcupSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: NcupLinker (бывший DressRetroLinker)
// ============================================================================

class NcupLinker {
  static Future<bool> NcupOpen(Uri NcupUri) async {
    try {
      if (await launchUrl(
        NcupUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        NcupUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (NcupError) {
      debugPrint('DressRetroLinker error: $NcupError; url=$NcupUri');
      try {
        return await launchUrl(
          NcupUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> NcupFcmBackgroundHandler(RemoteMessage NcupMessage) async {
  debugPrint("Spin ID: ${NcupMessage.messageId}");
  debugPrint("Spin Data: ${NcupMessage.data}");
}

// ============================================================================
// NcupDeviceProfile (бывший DressRetroDeviceProfile)
// ============================================================================

class NcupDeviceProfile {
  String? NcupDeviceId;
  String? NcupSessionId = 'wheel-one-off';
  String? NcupPlatformKind;
  String? NcupOsBuild;
  String? NcupAppVersion;
  String? NcupLocaleCode;
  String? NcupTimezoneName;
  bool NcupPushEnabled = true;

  Future<void> NcupInitialize() async {
    final DeviceInfoPlugin NcupInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo NcupAndroidInfo =
      await NcupInfoPlugin.androidInfo;
      NcupDeviceId = NcupAndroidInfo.id;
      NcupPlatformKind = 'android';
      NcupOsBuild = NcupAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo NcupIosInfo = await NcupInfoPlugin.iosInfo;
      NcupDeviceId = NcupIosInfo.identifierForVendor;
      NcupPlatformKind = 'ios';
      NcupOsBuild = NcupIosInfo.systemVersion;
    }

    final PackageInfo NcupPackageInfo = await PackageInfo.fromPlatform();
    NcupAppVersion = NcupPackageInfo.version;
    NcupLocaleCode = Platform.localeName.split('_').first;
    NcupTimezoneName = NcupTimezone.local.name;
    NcupSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> NcupAsMap({String? NcupFcmToken}) => <String, dynamic>{
    'fcm_token': NcupFcmToken ?? 'missing_token',
    'device_id': NcupDeviceId ?? 'missing_id',
    'app_name': 'joiler',
    'instance_id': NcupSessionId ?? 'missing_session',
    'platform': NcupPlatformKind ?? 'missing_system',
    'os_version': NcupOsBuild ?? 'missing_build',
    'app_version': NcupAppVersion ?? 'missing_app',
    'language': NcupLocaleCode ?? 'en',
    'timezone': NcupTimezoneName ?? 'UTC',
    'push_enabled': NcupPushEnabled,
    "fthcashier": "true"
  };
}

// ============================================================================
// AppsFlyer шпион: NcupSpy (бывший DressRetroSpy)
// ============================================================================



// ============================================================================
// Мост для FCM токена: NcupFcmBridge (бывший DressRetroFcmBridge)
// ============================================================================

class NcupFcmBridge {
  final NcupLogger NcupLog = const NcupLogger();
  String? NcupToken;
  final List<void Function(String)> NcupWaiters = <void Function(String)>[];

  String? get NcupCurrentToken => NcupToken;

  NcupFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall NcupCall) async {
      if (NcupCall.method == 'setToken') {
        final String NcupTokenString = NcupCall.arguments as String;
        if (NcupTokenString.isNotEmpty) {
          NcupSetToken(NcupTokenString);
        }
      }
    });

    NcupRestoreToken();
  }

  Future<void> NcupRestoreToken() async {
    try {
      final SharedPreferences NcupPrefs = await SharedPreferences.getInstance();
      final String? NcupCached = NcupPrefs.getString(MetrCachedFcmKey);
      if (NcupCached != null && NcupCached.isNotEmpty) {
        NcupSetToken(NcupCached, NcupNotify: false);
      }
    } catch (_) {}
  }

  Future<void> NcupPersistToken(String NcupNewToken) async {
    try {
      final SharedPreferences NcupPrefs = await SharedPreferences.getInstance();
      await NcupPrefs.setString(MetrCachedFcmKey, NcupNewToken);
    } catch (_) {}
  }

  void NcupSetToken(
      String NcupNewToken, {
        bool NcupNotify = true,
      }) {
    NcupToken = NcupNewToken;
    NcupPersistToken(NcupNewToken);
    if (NcupNotify) {
      for (final void Function(String) NcupCallback
      in List<void Function(String)>.from(NcupWaiters)) {
        try {
          NcupCallback(NcupNewToken);
        } catch (NcupErr) {
          NcupLog.NcupLogWarn('fcm waiter error: $NcupErr');
        }
      }
      NcupWaiters.clear();
    }
  }

  Future<void> NcupWaitForToken(
      Function(String NcupTokenValue) NcupOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((NcupToken ?? '').isNotEmpty) {
        NcupOnToken(NcupToken!);
        return;
      }

      NcupWaiters.add(NcupOnToken);
    } catch (NcupErr) {
      NcupLog.NcupLogError('wheelWaitToken error: $NcupErr');
    }
  }
}

// ============================================================================
// NcupLoader (новый лоадер с буквой "N" и словом "CUP")
// ============================================================================

class NcupLoader extends StatefulWidget {
  const NcupLoader({Key? key}) : super(key: key);

  @override
  State<NcupLoader> createState() => _NcupLoaderState();
}

class _NcupLoaderState extends State<NcupLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController NcupController;

  static const Color NcupBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();

    NcupController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    NcupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NcupBackgroundColor,
      child: AnimatedBuilder(
        animation: NcupController,
        builder: (BuildContext context, Widget? child) {
          final double NcupPhase = NcupController.value * 2 * NcupMath.pi;
          return CustomPaint(
            painter: NcupLoaderPainter(
              NcupPhase: NcupPhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

///
/// NcupLoaderPainter
/// Рисует последовательную анимацию: мягкий фон + большая красная "N" и
/// маленькое слово "CUP" под буквой.
///
class NcupLoaderPainter extends CustomPainter {
  final double NcupPhase;

  NcupLoaderPainter({
    required this.NcupPhase,
  });

  @override
  void paint(Canvas NcupCanvas, Size NcupSize) {
    final double NcupWidth = NcupSize.width;
    final double NcupHeight = NcupSize.height;

    // Фон — тёмный с мягкими кругами, которые "дышат"
    final Paint NcupBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;
    NcupCanvas.drawRect(Offset.zero & NcupSize, NcupBackgroundPaint);

    final double NcupPulse = (NcupMath.sin(NcupPhase) + 1) / 2; // 0..1

    final Paint NcupCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.14 + 0.16 * NcupPulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(NcupWidth * 0.5, NcupHeight * 0.45),
          radius: NcupHeight * (0.4 + 0.15 * NcupPulse),
        ),
      );

    NcupCanvas.drawCircle(
      Offset(NcupWidth * 0.5, NcupHeight * 0.45),
      NcupHeight * (0.4 + 0.15 * NcupPulse),
      NcupCirclePaint,
    );

    // Вторая "аура"
    final Paint NcupOuterPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.redAccent.withOpacity(0.10 + 0.10 * (1 - NcupPulse)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(NcupWidth * 0.5, NcupHeight * 0.45),
          radius: NcupHeight * (0.55 + 0.10 * (1 - NcupPulse)),
        ),
      );
    NcupCanvas.drawCircle(
      Offset(NcupWidth * 0.5, NcupHeight * 0.45),
      NcupHeight * (0.55 + 0.10 * (1 - NcupPulse)),
      NcupOuterPaint,
    );

    // Большая красная буква "N"
    final double NcupBaseSize = NcupWidth * 0.35;
    final double NcupFontSize =
        NcupBaseSize + NcupPulse * (NcupBaseSize * 0.15);

    final String NcupLetter = 'N';
    final String NcupWord = 'CUP';

    final TextPainter NcupLetterPainter = TextPainter(
      text: TextSpan(
        text: NcupLetter,
        style: TextStyle(
          fontSize: NcupFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * NcupPulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: NcupWidth);

    final double NcupLetterX = (NcupWidth - NcupLetterPainter.width) / 2;
    final double NcupLetterY = (NcupHeight - NcupLetterPainter.height) / 2;

    final Offset NcupLetterOffset = Offset(NcupLetterX, NcupLetterY);

    // Дополнительный glow под буквой
    final Rect NcupLetterRect = Rect.fromCenter(
      center: Offset(NcupWidth / 2, NcupHeight / 2),
      width: NcupLetterPainter.width * 1.4,
      height: NcupLetterPainter.height * 1.6,
    );

    final Paint NcupGlowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        28 + 24 * NcupPulse,
      )
      ..color = Colors.red.withOpacity(0.7 + 0.2 * NcupPulse);

    NcupCanvas.saveLayer(NcupLetterRect, NcupGlowPaint);
    NcupLetterPainter.paint(NcupCanvas, NcupLetterOffset);
    NcupCanvas.restore();

    // Рисуем саму букву N поверх
    NcupLetterPainter.paint(NcupCanvas, NcupLetterOffset);

    // Небольшое слово "CUP" под буквой
    final double NcupCupFontSize = NcupWidth * 0.11;

    final TextPainter NcupCupPainter = TextPainter(
      text: TextSpan(
        text: NcupWord,
        style: TextStyle(
          fontSize: NcupCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * NcupPulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: NcupWidth);

    final double NcupCupX = (NcupWidth - NcupCupPainter.width) / 2;
    final double NcupCupY =
        NcupLetterY + NcupLetterPainter.height + NcupHeight * 0.03;

    final Offset NcupCupOffset = Offset(NcupCupX, NcupCupY);
    NcupCupPainter.paint(NcupCanvas, NcupCupOffset);
  }

  @override
  bool shouldRepaint(covariant NcupLoaderPainter NcupOldDelegate) =>
      NcupOldDelegate.NcupPhase != NcupPhase;
}

// ============================================================================
// Статистика (NcupFinalUrl / NcupPostStat) — строки не меняем
// ============================================================================

Future<String> NcupFinalUrl(
    String NcupStartUrl, {
      int NcupMaxHops = 10,
    }) async {
  final HttpClient NcupClient = HttpClient();

  try {
    Uri NcupCurrentUri = Uri.parse(NcupStartUrl);

    for (int NcupI = 0; NcupI < NcupMaxHops; NcupI++) {
      final HttpClientRequest NcupRequest =
      await NcupClient.getUrl(NcupCurrentUri);
      NcupRequest.followRedirects = false;
      final HttpClientResponse NcupResponse = await NcupRequest.close();

      if (NcupResponse.isRedirect) {
        final String? NcupLoc =
        NcupResponse.headers.value(HttpHeaders.locationHeader);
        if (NcupLoc == null || NcupLoc.isEmpty) break;

        final Uri NcupNextUri = Uri.parse(NcupLoc);
        NcupCurrentUri = NcupNextUri.hasScheme
            ? NcupNextUri
            : NcupCurrentUri.resolveUri(NcupNextUri);
        continue;
      }

      return NcupCurrentUri.toString();
    }

    return NcupCurrentUri.toString();
  } catch (NcupError) {
    debugPrint('wheelFinalUrl error: $NcupError');
    return NcupStartUrl;
  } finally {
    NcupClient.close(force: true);
  }
}

Future<void> NcupPostStat({
  required String NcupEvent,
  required int NcupTimeStart,
  required String NcupUrl,
  required int NcupTimeFinish,
  required String NcupAppSid,
  int? NcupFirstPageTs,
}) async {
  try {
    final String NcupResolvedUrl = await NcupFinalUrl(NcupUrl);
    final Map<String, dynamic> NcupPayload = <String, dynamic>{
      'event': NcupEvent,
      'timestart': NcupTimeStart,
      'timefinsh': NcupTimeFinish,
      'url': NcupResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$NcupAppSid/$NcupTimeStart',
    };

    debugPrint('wheelStat $NcupPayload');

    final http.Response NcupResp = await http.post(
      Uri.parse('$MetrStatEndpoint/$NcupAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(NcupPayload),
    );

    debugPrint('wheelStat resp=${NcupResp.statusCode} body=${NcupResp.body}');
  } catch (NcupError) {
    debugPrint('wheelPostStat error: $NcupError');
  }
}

// ============================================================================
// WebView-экран: NcupTableView (бывший DressRetroTableView)
// ============================================================================

class NcupTableView extends StatefulWidget with WidgetsBindingObserver {
  String NcupStartingUrl;
  NcupTableView(this.NcupStartingUrl, {super.key});

  @override
  State<NcupTableView> createState() => _NcupTableViewState(NcupStartingUrl);
}

class _NcupTableViewState extends State<NcupTableView>
    with WidgetsBindingObserver {
  _NcupTableViewState(this.NcupCurrentUrl);

  final NcupVault NcupVaultInstance = NcupVault();

  late InAppWebViewController NcupWebViewController;
  String? NcupPushToken;
  final NcupDeviceProfile NcupDeviceProfileInstance = NcupDeviceProfile();

  bool NcupOverlayBusy = false;
  String NcupCurrentUrl;
  DateTime? NcupLastPausedAt;

  bool NcupLoadedOnceSent = false;
  int? NcupFirstPageTimestamp;
  int NcupStartLoadTimestamp = 0;

  final Set<String> NcupExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> NcupExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(NcupFcmBackgroundHandler);

    NcupFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    NcupInitPushAndGetToken();
    NcupDeviceProfileInstance.NcupInitialize();
    NcupWireForegroundPushHandlers();
    NcupBindPlatformNotificationTap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState NcupState) {
    if (NcupState == AppLifecycleState.paused) {
      NcupLastPausedAt = DateTime.now();
    }
    if (NcupState == AppLifecycleState.resumed) {
      if (Platform.isIOS && NcupLastPausedAt != null) {
        final DateTime NcupNow = DateTime.now();
        final Duration NcupDrift = NcupNow.difference(NcupLastPausedAt!);
        if (NcupDrift > const Duration(minutes: 25)) {
          NcupForceReloadToLobby();
        }
      }
      NcupLastPausedAt = null;
    }
  }

  void NcupForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration NcupDuration) {
      if (!mounted) return;
      // Здесь можно вернуть в лобби (MafiaHarbor / CaptainHarbor / BillHarbor),
      // если нужно.
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void NcupWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage NcupMsg) {
      if (NcupMsg.data['uri'] != null) {
        NcupNavigateTo(NcupMsg.data['uri'].toString());
      } else {
        NcupReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage NcupMsg) {
      if (NcupMsg.data['uri'] != null) {
        NcupNavigateTo(NcupMsg.data['uri'].toString());
      } else {
        NcupReturnToCurrentUrl();
      }
    });
  }

  void NcupNavigateTo(String NcupNewUrl) async {
    await NcupWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(NcupNewUrl)),
    );
  }

  void NcupReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      NcupWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(NcupCurrentUrl)),
      );
    });
  }

  Future<void> NcupInitPushAndGetToken() async {
    final FirebaseMessaging NcupFm = FirebaseMessaging.instance;
    await NcupFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    NcupPushToken = await NcupFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void NcupBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall NcupCall) async {
      if (NcupCall.method == "onNotificationTap") {
        final Map<String, dynamic> NcupPayload =
        Map<String, dynamic>.from(NcupCall.arguments);
        debugPrint("URI from platform tap: ${NcupPayload['uri']}");
        final String? NcupUriString = NcupPayload["uri"]?.toString();
        if (NcupUriString != null && !NcupUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext NcupContext) =>
                  NcupTableView(NcupUriString),
            ),
                (Route<dynamic> NcupRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    NcupBindPlatformNotificationTap();

    final bool NcupIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: NcupIsDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(NcupCurrentUrl),
              ),
              onWebViewCreated: (InAppWebViewController NcupController) {
                NcupWebViewController = NcupController;

                NcupWebViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (List<dynamic> NcupArgs) {
                    NcupVaultInstance.NcupLoggerInstance
                        .NcupLogInfo("JS Args: $NcupArgs");
                    try {
                      return NcupArgs.reduce(
                              (dynamic NcupV, dynamic NcupE) => NcupV + NcupE);
                    } catch (_) {
                      return NcupArgs.toString();
                    }
                  },
                );
              },
              onLoadStart: (
                  InAppWebViewController NcupController,
                  Uri? NcupUri,
                  ) async {
                NcupStartLoadTimestamp = DateTime.now().millisecondsSinceEpoch;

                if (NcupUri != null) {
                  if (NcupKit.NcupLooksLikeBareMail(NcupUri)) {
                    try {
                      await NcupController.stopLoading();
                    } catch (_) {}
                    final Uri NcupMailto = NcupKit.NcupToMailto(NcupUri);
                    await NcupLinker.NcupOpen(
                      NcupKit.NcupGmailize(NcupMailto),
                    );
                    return;
                  }

                  final String NcupScheme = NcupUri.scheme.toLowerCase();
                  if (NcupScheme != 'http' && NcupScheme != 'https') {
                    try {
                      await NcupController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (
                  InAppWebViewController NcupController,
                  Uri? NcupUri,
                  ) async {
                await NcupController.evaluateJavascript(
                  source: "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  NcupCurrentUrl = NcupUri?.toString() ?? NcupCurrentUrl;
                });

                Future<void>.delayed(const Duration(seconds: 20), () {
                  NcupSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading: (
                  InAppWebViewController NcupController,
                  NavigationAction NcupNav,
                  ) async {
                final Uri? NcupUri = NcupNav.request.url;
                if (NcupUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (NcupKit.NcupLooksLikeBareMail(NcupUri)) {
                  final Uri NcupMailto = NcupKit.NcupToMailto(NcupUri);
                  await NcupLinker.NcupOpen(
                    NcupKit.NcupGmailize(NcupMailto),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String NcupScheme = NcupUri.scheme.toLowerCase();

                if (NcupScheme == 'mailto') {
                  await NcupLinker.NcupOpen(
                    NcupKit.NcupGmailize(NcupUri),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                if (NcupScheme == 'tel') {
                  await launchUrl(
                    NcupUri,
                    mode: LaunchMode.externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String NcupHost = NcupUri.host.toLowerCase();
                final bool NcupIsSocial =
                    NcupHost.endsWith('facebook.com') ||
                        NcupHost.endsWith('instagram.com') ||
                        NcupHost.endsWith('twitter.com') ||
                        NcupHost.endsWith('x.com');

                if (NcupIsSocial) {
                  await NcupLinker.NcupOpen(NcupUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (NcupIsExternalDestination(NcupUri)) {
                  final Uri NcupMapped = NcupMapExternalToHttp(NcupUri);
                  await NcupLinker.NcupOpen(NcupMapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (NcupScheme != 'http' && NcupScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (
                  InAppWebViewController NcupController,
                  CreateWindowAction NcupReq,
                  ) async {
                final Uri? NcupUrl = NcupReq.request.url;
                if (NcupUrl == null) return false;

                if (NcupKit.NcupLooksLikeBareMail(NcupUrl)) {
                  final Uri NcupMail = NcupKit.NcupToMailto(NcupUrl);
                  await NcupLinker.NcupOpen(
                    NcupKit.NcupGmailize(NcupMail),
                  );
                  return false;
                }

                final String NcupScheme = NcupUrl.scheme.toLowerCase();

                if (NcupScheme == 'mailto') {
                  await NcupLinker.NcupOpen(
                    NcupKit.NcupGmailize(NcupUrl),
                  );
                  return false;
                }

                if (NcupScheme == 'tel') {
                  await launchUrl(
                    NcupUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  return false;
                }

                final String NcupHost = NcupUrl.host.toLowerCase();
                final bool NcupIsSocial =
                    NcupHost.endsWith('facebook.com') ||
                        NcupHost.endsWith('instagram.com') ||
                        NcupHost.endsWith('twitter.com') ||
                        NcupHost.endsWith('x.com');

                if (NcupIsSocial) {
                  await NcupLinker.NcupOpen(NcupUrl);
                  return false;
                }

                if (NcupIsExternalDestination(NcupUrl)) {
                  final Uri NcupMapped = NcupMapExternalToHttp(NcupUrl);
                  await NcupLinker.NcupOpen(NcupMapped);
                  return false;
                }

                if (NcupScheme == 'http' || NcupScheme == 'https') {
                  NcupController.loadUrl(
                    urlRequest: URLRequest(url: WebUri(NcupUrl.toString())),
                  );
                }

                return false;
              },
            ),
            if (NcupOverlayBusy)
              const Positioned.fill(
                child: NcupLoader(), // ЗДЕСЬ ЗАМЕНИЛ loader
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool NcupIsExternalDestination(Uri NcupUri) {
    final String NcupScheme = NcupUri.scheme.toLowerCase();
    if (NcupExternalSchemes.contains(NcupScheme)) {
      return true;
    }

    if (NcupScheme == 'http' || NcupScheme == 'https') {
      final String NcupHost = NcupUri.host.toLowerCase();
      if (NcupExternalHosts.contains(NcupHost)) {
        return true;
      }
      if (NcupHost.endsWith('t.me')) return true;
      if (NcupHost.endsWith('wa.me')) return true;
      if (NcupHost.endsWith('m.me')) return true;
      if (NcupHost.endsWith('signal.me')) return true;
      if (NcupHost.endsWith('facebook.com')) return true;
      if (NcupHost.endsWith('instagram.com')) return true;
      if (NcupHost.endsWith('twitter.com')) return true;
      if (NcupHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri NcupMapExternalToHttp(Uri NcupUri) {
    final String NcupScheme = NcupUri.scheme.toLowerCase();

    if (NcupScheme == 'tg' || NcupScheme == 'telegram') {
      final Map<String, String> NcupQp = NcupUri.queryParameters;
      final String? NcupDomain = NcupQp['domain'];
      if (NcupDomain != null && NcupDomain.isNotEmpty) {
        return Uri.https('t.me', '/$NcupDomain', <String, String>{
          if (NcupQp['start'] != null) 'start': NcupQp['start']!,
        });
      }
      final String NcupPath = NcupUri.path.isNotEmpty ? NcupUri.path : '';
      return Uri.https(
        't.me',
        '/$NcupPath',
        NcupUri.queryParameters.isEmpty ? null : NcupUri.queryParameters,
      );
    }

    if (NcupScheme == 'whatsapp') {
      final Map<String, String> NcupQp = NcupUri.queryParameters;
      final String? NcupPhone = NcupQp['phone'];
      final String? NcupText = NcupQp['text'];
      if (NcupPhone != null && NcupPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${NcupKit.NcupDigitsOnly(NcupPhone)}',
          <String, String>{
            if (NcupText != null && NcupText.isNotEmpty) 'text': NcupText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (NcupText != null && NcupText.isNotEmpty) 'text': NcupText,
        },
      );
    }

    if (NcupScheme == 'bnl') {
      final String NcupNewPath = NcupUri.path.isNotEmpty ? NcupUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$NcupNewPath',
        NcupUri.queryParameters.isEmpty ? null : NcupUri.queryParameters,
      );
    }

    return NcupUri;
  }

  Future<void> NcupSendLoadedOnce() async {
    if (NcupLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int NcupNow = DateTime.now().millisecondsSinceEpoch;

    // тут, как и было, можешь добавить NcupPostStat при необходимости

    NcupLoadedOnceSent = true;
  }
}