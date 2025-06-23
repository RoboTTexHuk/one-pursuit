import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart' show AppTrackingTransparency, TrackingStatus;
import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as zzz;
import 'package:timezone/timezone.dart' as zzt;
import 'package:http/http.dart' as zhttp;

import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;
import 'package:url_launcher/url_launcher_string.dart';

import 'main.dart' show VUVUZELA;

// FCM Background Handler
@pragma('vm:entry-point')
Future<void> _tigerMsgHandler(RemoteMessage mangoMsg) async {
  print("TBG Message: ${mangoMsg.messageId}");
  print("TBG Data: ${mangoMsg.data}");
  // Any background handler code here
}

class QuantumWebWatermelon extends StatefulWidget {
  String papayaUrl;
  QuantumWebWatermelon(this.papayaUrl, {super.key});
  @override
  State<QuantumWebWatermelon> createState() => _QuantumWebWatermelonState(papayaUrl);
}

class _QuantumWebWatermelonState extends State<QuantumWebWatermelon> {
  _QuantumWebWatermelonState(this._kiwiUrl);
  late InAppWebViewController _blueberryCtrl;
  String? _tomatoToken;
  String? _figToken;
  String? _bananaDevId;
  String? _apricotInstanceId;
  String? _plumPlatform;
  String? _oliveOsVer;
  String? _lycheeVer;
  String? _cherryLang;
  String? _dateTz;
  bool _peachPush = true;
  bool _pearLoading = false;
  var _melonBlockerOn = true;
  final List<ContentBlocker> _radishBlockers = [];
  String _kiwiUrl;

  @override
  void initState() {
    super.initState();



    FirebaseMessaging.onBackgroundMessage(_tigerMsgHandler);
    _onionInitATT();
    _limeInitAppsFlyer();
    _paprikaSetupChannels();
    _cabbageGatherData();
    _carrotInitFCM();

    FirebaseMessaging.onMessage.listen((RemoteMessage potat) {
      if (potat.data['uri'] != null) {
        _broccoliLoadUrl(potat.data['uri'].toString());
      } else {
        _spinachResetUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage beet) {
      if (beet.data['uri'] != null) {
        _broccoliLoadUrl(beet.data['uri'].toString());
      } else {
        _spinachResetUrl();
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      _onionInitATT();
    });
    Future.delayed(const Duration(seconds: 6), () {
      _dragonfruitSendRaw();
    });
  }

  void _paprikaSetupChannels() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> parsley = Map<String, dynamic>.from(call.arguments);
        if (parsley["uri"] != null && !parsley["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => QuantumWebWatermelon(parsley["uri"])),
                (route) => false,
          );
        }
      }
    });
  }

  void _broccoliLoadUrl(String gherkin) async {
    if (_blueberryCtrl != null) {
      await _blueberryCtrl.loadUrl(
        urlRequest: URLRequest(url: WebUri(gherkin)),
      );
    }
  }

  void _spinachResetUrl() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_blueberryCtrl != null) {
        _blueberryCtrl.loadUrl(
          urlRequest: URLRequest(url: WebUri(_kiwiUrl)),
        );
      }
    });
  }

  Future<void> _carrotInitFCM() async {
    FirebaseMessaging melonFM = FirebaseMessaging.instance;
    NotificationSettings potatoSettings = await melonFM.requestPermission(alert: true, badge: true, sound: true);
    _figToken = await melonFM.getToken();
  }

  Future<void> _onionInitATT() async {
    final TrackingStatus celery = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (celery == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
    final uuid = await AppTrackingTransparency.getAdvertisingIdentifier();
    print("VEG_UUID: $uuid");
  }

  AppsflyerSdk? _lemonAF;
  String _grapeAFID = "";
  String _pomegranateConv = "";

  void _limeInitAppsFlyer() {
    final AppsFlyerOptions tangerineOpts = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6747666553",
      showDebug: true,
    );
    _lemonAF = AppsflyerSdk(tangerineOpts);
    _lemonAF?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _lemonAF?.startSDK(
      onSuccess: () => print("AF OK"),
      onError: (int code, String msg) => print("AF ERR $code $msg"),
    );
    _lemonAF?.onInstallConversionData((res) {
      setState(() {
        _pomegranateConv = res.toString();
        _grapeAFID = res['payload']['af_status'].toString();
      });
    });
    _lemonAF?.getAppsFlyerUID().then((value) {
      setState(() {
        _grapeAFID = value.toString();
      });
    });
  }

  Future<void> _dragonfruitSendRaw() async {
    print("POM_DATA: $_pomegranateConv");
    final durianJson = {
      "content": {
        "af_data": "$_pomegranateConv",
        "af_id": "$_grapeAFID",
        "fb_app_name": "onepursuit",
        "app_name": "onepursuit",
        "deep": null,
        "bundle_identifier": "com.apursu.onepursuit.onepursuit",
        "app_version": "1.0.0",
        "apple_id": "6747666553",
        "device_id": _bananaDevId ?? "default_device_id",
        "instance_id": _apricotInstanceId ?? "default_instance_id",
        "platform": _plumPlatform ?? "unknown_platform",
        "os_version": _oliveOsVer ?? "default_os_version",
        "app_version": _lycheeVer ?? "default_app_version",
        "language": _cherryLang ?? "en",
        "timezone": _dateTz ?? "UTC",
        "push_enabled": _peachPush,
        "useruid": "$_grapeAFID",
      },
    };

    final jackfruitString = jsonEncode(durianJson);
    print("MY_FRUIT_JSON $jackfruitString");
    await _blueberryCtrl.evaluateJavascript(
      source: "sendRawData(${jsonEncode(jackfruitString)});",
    );
  }

  Future<void> _cabbageGatherData() async {
    try {
      final dragonfruitDevice = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final carrotAndroid = await dragonfruitDevice.androidInfo;
        _bananaDevId = carrotAndroid.id;
        _plumPlatform = "android";
        _oliveOsVer = carrotAndroid.version.release;
      } else if (Platform.isIOS) {
        final appleIOS = await dragonfruitDevice.iosInfo;
        _bananaDevId = appleIOS.identifierForVendor;
        _plumPlatform = "ios";
        _oliveOsVer = appleIOS.systemVersion;
      }
      final celeryInfo = await PackageInfo.fromPlatform();
      _lycheeVer = celeryInfo.version;
      _cherryLang = Platform.localeName.split('_')[0];
      _dateTz = zzt.local.name;
      _apricotInstanceId = "d67f89a0-1234-5678-9abc-def012345678";
      if (_blueberryCtrl != null) {
        // You can send data to web here if needed
      }
    } catch (e) {
      debugPrint("VEG_INIT_ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              allowsPictureInPictureMediaPlayback: true,
              useOnDownloadStart: true,
              contentBlockers: _radishBlockers,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(_kiwiUrl)),
            onWebViewCreated: (ctrl) {
              _blueberryCtrl = ctrl;
              _blueberryCtrl.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS_VEG_ARGS: $args");
                    return args.reduce((curr, next) => curr + next);
                  });
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: "console.log('Hello from JS!');",
              );
              // You can send data after load if needed
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_pearLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}