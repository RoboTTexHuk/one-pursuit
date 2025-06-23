import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:app_tracking_transparency/app_tracking_transparency.dart'
    show AppTrackingTransparency, TrackingStatus;
import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onepursuit/pushi.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:percent_indicator/circular_percent_indicator.dart' show CircularPercentIndicator, CircularStrokeCap;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

// --------- BLOC для ATT ----------
enum AttPermissionEvent { request }
enum AttPermissionState { unknown, granted, denied, loading }

class AttPermissionBloc extends Bloc<AttPermissionEvent, AttPermissionState> {
  AttPermissionBloc() : super(AttPermissionState.unknown) {
    on<AttPermissionEvent>((event, emit) async {
      if (event == AttPermissionEvent.request) {
        emit(AttPermissionState.loading);
        try {
          await AppTrackingTransparency.requestTrackingAuthorization();
          final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
          if (status == TrackingStatus.authorized) {
            emit(AttPermissionState.granted);
          } else {
            emit(AttPermissionState.denied);
          }
        } catch (_) {
          emit(AttPermissionState.denied);
        }
      }
    });
  }
}

// --------- ТОЧКА ВХОДА ----------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMsgHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tzData.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();
  final bool attSeen = prefs.getBool('att_seen') ?? false;

  runApp(
    MaterialApp(
      home: BlocProvider(
        create: (_) => AttPermissionBloc(),
        child: attSeen ? const PushInitScreen() : const AttPermissionScreen(),
      ),
      debugShowCheckedModeBanner: false,
    ),
  );
}

// --------- ЭКРАН ATT Permission ----------
class AttPermissionScreen extends StatelessWidget {
  const AttPermissionScreen({super.key});

  Future<void> _saveAttSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('att_seen', true);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AttPermissionBloc, AttPermissionState>(
      listener: (context, state) async {
        if (state == AttPermissionState.granted ||
            state == AttPermissionState.denied) {
          await _saveAttSeen();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PushInitScreen()),
          );
        }
      },
      builder: (context, state) {
        if (state == AttPermissionState.loading) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Container(
              width: 350,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.blue[800],
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 56, color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'Why do we request permission to track activity?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'We use your data to provide more relevant ads, special offers, and game bonuses. For example, we may show you discounts that match your interests or remind you about unfinished games. Your data will never be sold or shared with third parties for unrelated purposes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        context
                            .read<AttPermissionBloc>()
                            .add(AttPermissionEvent.request);
                      },
                      child: const Text('Next'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You can always change your choice in device settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --------- PUSH INIT SCREEN ----------
class PushInitScreen extends StatefulWidget {
  const PushInitScreen({Key? key}) : super(key: key);
  @override
  State<PushInitScreen> createState() => _PushInitScreenState();
}

class _PushInitScreenState extends State<PushInitScreen> {
  final NotificationBloc _notifBloc = NotificationBloc();
  bool _navigated = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _notifBloc.listenForToken((token) {
      _proceed(token);
    });
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      _proceed('');
    });
  }

  void _proceed(String token) {
    if (_navigated) return;
    _navigated = true;
    _timeoutTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MainWebViewScreen(userPushToken: token),
      ),
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          height: 100,
          width: 100,
          child: Center(
            child: Container(),
          ),
        ),
      ),
    );
  }
}

// --------- NOTIFICATION BLOC ----------
class NotificationBloc extends ChangeNotifier {
  String? _pushToken;

  void listenForToken(Function(String token) onToken) {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String token = call.arguments as String;
        onToken(token);
      }
    });
  }
}

// --------- DEVICE INFO MANAGER ----------
class DeviceManager {
  String? deviceId;
  String? instanceId = "instance-unique-id";
  String? platformType;
  String? platformVersion;
  String? appVersion;
  String? language;
  String? timezone;
  bool notificationsEnabled = true;

  Future<void> initDevice() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
      platformType = "android";
      platformVersion = info.version.release;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
      platformType = "ios";
      platformVersion = info.systemVersion;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version;
    language = Platform.localeName.split('_')[0];
    timezone = tz.local.name;
  }

  Map<String, dynamic> toMap({String? fcmToken}) {
    return {
      "fcm_token": fcmToken ?? 'no_token',
      "device_id": deviceId ?? 'no_device',
      "app_name": "onepursuit",
      "instance_id": instanceId ?? 'no_instance',
      "platform": platformType ?? 'no_type',
      "os_version": platformVersion ?? 'no_os',
      "app_version": appVersion ?? 'no_app',
      "language": language ?? 'en',
      "timezone": timezone ?? 'UTC',
      "push_enabled": notificationsEnabled,
    };
  }
}

// --------- APPSFLYER MANAGER ----------
class AppsFlyerManager extends ChangeNotifier {
  AppsflyerSdk? _sdk;
  String appsFlyerId = "";
  String conversionData = "";

  void initialize(VoidCallback onUpdate) {
    final options = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6747666553",
      showDebug: true,
    );
    _sdk = AppsflyerSdk(options);
    _sdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _sdk?.startSDK(
      onSuccess: () => print("AppsFlyer started"),
      onError: (int code, String msg) => print("AppsFlyer error $code $msg"),
    );
    _sdk?.onInstallConversionData((result) {
      conversionData = result.toString();
      onUpdate();
    });
    _sdk?.getAppsFlyerUID().then((val) {
      appsFlyerId = val.toString();
      onUpdate();
    });
  }
}

// --------- MAIN WEBVIEW SCREEN ----------
class MainWebViewScreen extends StatefulWidget {
  final String? userPushToken;
  const MainWebViewScreen({super.key, required this.userPushToken});

  @override
  State<MainWebViewScreen> createState() => _MainWebViewScreenState();
}

class _MainWebViewScreenState extends State<MainWebViewScreen> {
  late InAppWebViewController _webController;
  bool _isLoading = false;
  final String _mainUrl = "https://getgame.pursuit-game.autos/";

  final DeviceManager _deviceManager = DeviceManager();
  final AppsFlyerManager _appsFlyerManager = AppsFlyerManager();

  @override
  void initState() {
    super.initState();
    _startInit();
  }

  void _startInit() {
    _startLoadingProgress();
    _setupFirebasePush();
    _setupATT();

    _appsFlyerManager.initialize(() => setState(() {}));
    _setupNotificationChannel();
    _initDevice();
    Future.delayed(const Duration(seconds: 2), _setupATT);
    Future.delayed(const Duration(seconds: 6), () {
      _sendDeviceDataToWeb();
      _sendAppsFlyerDataToWeb();
    });
  }

  void _setupFirebasePush() {
    FirebaseMessaging.onMessage.listen((msg) {
      final uri = msg.data['uri'];
      if (uri != null) {
        _loadWebUrl(uri.toString());
      } else {
        _reloadMainWeb();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final uri = msg.data['uri'];
      if (uri != null) {
        _loadWebUrl(uri.toString());
      } else {
        _reloadMainWeb();
      }
    });
  }

  void _setupNotificationChannel() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> data = Map<String, dynamic>.from(call.arguments);
        final url = data["uri"];
        if (url != null && !url.contains("Нет URI")) {
               Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) =>QuantumWebWatermelon( url)),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _initDevice() async {
    try {
      await _deviceManager.initDevice();
      await _initPushMessaging();
      if (_webController != null) {
        _sendDeviceDataToWeb();
      }
    } catch (e) {
      debugPrint("Device data init error: $e");
    }
  }

  Future<void> _initPushMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _setupATT() async {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
    final uuid = await AppTrackingTransparency.getAdvertisingIdentifier();
    print("ATT AdvertisingIdentifier: $uuid");
  }

  void _loadWebUrl(String uri) async {
    if (_webController != null) {
      await _webController.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri)),
      );
    }
  }

  void _reloadMainWeb() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_webController != null) {
        _webController.loadUrl(
          urlRequest: URLRequest(url: WebUri(_mainUrl)),
        );
      }
    });
  }
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _sendDeviceDataToWeb() async {
    setState(() => _isLoading = true);
    try {
      final deviceMap = _deviceManager.toMap(fcmToken: widget.userPushToken);
      await _webController.evaluateJavascript(source: '''
      localStorage.setItem('app_data', JSON.stringify(${jsonEncode(deviceMap)}));
      ''');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  final List<String> BANANA_AD_URLS = [
    ".*.doubleclick.net/.*",
    ".*.ads.pubmatic.com/.*",
    ".*.googlesyndication.com/.*",
    ".*.google-analytics.com/.*",
    ".*.adservice.google.*/.*",
    ".*.adbrite.com/.*",
    ".*.exponential.com/.*",
    ".*.quantserve.com/.*",
    ".*.scorecardresearch.com/.*",
    ".*.zedo.com/.*",
    ".*.adsafeprotected.com/.*",
    ".*.teads.tv/.*",
    ".*.outbrain.com/.*",
  ];

  List<ContentBlocker> getContentBlockers() {
    final contentBlockers = <ContentBlocker>[];

    for (final adUrlFilter in BANANA_AD_URLS) {
      contentBlockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: adUrlFilter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }



    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".cookie",
          resourceType: [
            //   ContentBlockerTriggerResourceType.IMAGE,
            ContentBlockerTriggerResourceType.RAW,
          ],
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
          selector: ".notification",
        ),
      ),
    );

    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".cookie",
          resourceType: [
            //   ContentBlockerTriggerResourceType.IMAGE,
            ContentBlockerTriggerResourceType.RAW,
          ],
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info",
        ),
      ),
    );
    // apply the "display: none" style to some HTML elements
    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*"),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".banner, .banners, .ads, .ad, .advert",
        ),
      ),
    );

    return contentBlockers;
  }
  Future<void> _sendAppsFlyerDataToWeb() async {
    final data = {
      "content": {
        "af_data": _appsFlyerManager.conversionData,
        "af_id": _appsFlyerManager.appsFlyerId,
        "fb_app_name": "onepursuit",
        "app_name": "onepursuit",
        "deep": null,
        "bundle_identifier": "com.apursu.onepursuit.onepursuit",
        "app_version": "1.0.0",
        "apple_id": "6747666553",
        "fcm_token": widget.userPushToken ?? "no_token",
        "device_id": _deviceManager.deviceId ?? "no_device",
        "instance_id": _deviceManager.instanceId ?? "no_instance",
        "platform": _deviceManager.platformType ?? "no_type",
        "os_version": _deviceManager.platformVersion ?? "no_os",
        "app_version": _deviceManager.appVersion ?? "no_app",
        "language": _deviceManager.language ?? "en",
        "timezone": _deviceManager.timezone ?? "UTC",
        "push_enabled": _deviceManager.notificationsEnabled,
        "useruid": _appsFlyerManager.appsFlyerId,
      },
    };
    final jsonString = jsonEncode(data);
    print("SendRawData: $jsonString");

    await _webController.evaluateJavascript(
      source: "sendRawData(${jsonEncode(jsonString)});",
    );
  }
  bool _showWebView = false;
  double _percent = 0.0;
  late Timer _timer;
  final int _delay = 6; // секунд
  void _startLoadingProgress() {
    int tick = 0;
    _percent = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        tick++;
        _percent = tick / (_delay * 10);
        if (_percent >= 1.0) {
          _percent = 1.0;
          _showWebView = true;
          _timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _setupNotificationChannel();
    return Scaffold(
      backgroundColor: Colors.black,
      body:
           SafeArea(
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              InAppWebView(
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  disableDefaultErrorPage: true,
                  contentBlockers: getContentBlockers(),
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  allowsPictureInPictureMediaPlayback: true,
                  useOnDownloadStart: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                initialUrlRequest: URLRequest(url: WebUri(_mainUrl)),
                onWebViewCreated: (controller) {
                  _webController = controller;
                  _webController.addJavaScriptHandler(
                    handlerName: 'onServerResponse',
                    callback: (args) {
                      print("JS args: $args");
                      return args.reduce((curr, next) => curr + next);
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  setState(() => _isLoading = true);
                },
                onLoadStop: (controller, url) async {
                  await controller.evaluateJavascript(
                    source: "console.log('Hello from JS!');",
                  );
                  await _sendDeviceDataToWeb();
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              if (_isLoading)
                const Center(
                  child: SizedBox(
                    height: 80,
                    width: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                      backgroundColor: Colors.grey,
                    ),
                  ),
                ),
                  Visibility(
                    visible: !_showWebView,
                    child: Center(
                    child: CircularPercentIndicator(
                        radius: 60.0,
                        lineWidth: 8.0,
                        percent: _percent,
                        animation: true,
                        animateFromLastPercent: true,
                        circularStrokeCap: CircularStrokeCap.round,
                        progressColor: Colors.blueAccent,
                        backgroundColor: Colors.grey.shade800,
                        center: Text(
                        "${(_percent * 100).round()}%",
                        style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                        ),
                        ),
                        ),
                  ),
            ],
          ),
        ),

           ) );
  }
}

// --------- FCM BACKGROUND HANDLER ----------
@pragma('vm:entry-point')
Future<void> _firebaseMsgHandler(RemoteMessage message) async {
  print("BG Message: ${message.messageId}");
  print("BG Data: ${message.data}");
}