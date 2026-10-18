import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _deviceChannel = MethodChannel('mobile_codex/device');

class RpcFailure implements Exception {
  RpcFailure(this.code, this.message, this.requestId);
  final String code, message, requestId;
  @override
  String toString() => '$message ($code · $requestId)';
}

class BridgeClient extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final pending = <String, Completer<Map<String, dynamic>>>{};
  Map<String, dynamic>? credentials;
  WebSocket? socket;
  HttpClient? http;
  Timer? retry;
  String status = '未连接';
  int counter = 0, retryAttempt = 0;
  bool closed = false;

  /// Returns a stable, human-readable device label for the trusted-device list.
  /// Native platforms provide the hardware model; tests and unsupported
  /// platforms use an OS-only fallback without blocking pairing.
  Future<String> deviceLabel() async {
    try {
      final value = await _deviceChannel.invokeMethod<String>('model');
      if (value != null && value.trim().isNotEmpty) return value.trim();
    } catch (_) {
      // The channel is unavailable in Dart tests and on unsupported targets.
    }
    final version = Platform.operatingSystemVersion.trim();
    final os = Platform.isIOS
        ? 'iOS'
        : Platform.isAndroid
        ? 'Android'
        : Platform.operatingSystem;
    return version.isEmpty ? os : '$os ($version)';
  }

  HttpClient pinnedClient(String fingerprint) {
    final expected = fingerprint.replaceAll(':', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw const FormatException('电脑证书 fingerprint 必须是 SHA-256');
    }
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    client.badCertificateCallback = (certificate, host, port) =>
        sha256.convert(certificate.der).toString() == expected;
    return client;
  }

  Future<void> restore() async {
    final saved = await storage.read(key: 'bridge');
    if (saved != null) {
      credentials = Map<String, dynamic>.from(jsonDecode(saved));
      await connect();
    }
  }

  Future<void> pair(String pairingJson, String name) async {
    final pairing = Map<String, dynamic>.from(jsonDecode(pairingJson));
    final url = Uri.parse(pairing['url'] as String);
    if (url.scheme != 'wss' || url.path != '/ws') {
      throw const FormatException('配对地址必须是 wss://电脑:端口/ws');
    }
    final client = pinnedClient(pairing['fingerprint'] as String);
    try {
      final request = await client.postUrl(
        url.replace(scheme: 'https', path: '/pair'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'id': pairing['id'],
          'secret': pairing['secret'],
          'name': name,
        }),
      );
      final response = await request.close();
      final result = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(response).join()),
      );
      if (response.statusCode != 200) {
        throw Exception(result['error']?['message'] ?? '配对失败');
      }
      credentials = {
        'url': url.toString(),
        'fingerprint': pairing['fingerprint'],
        'token': result['token'],
        'deviceId': result['deviceId'],
        'deviceName': name,
      };
      await storage.write(key: 'bridge', value: jsonEncode(credentials));
    } finally {
      client.close();
    }
    await connect();
  }

  Future<void> connect() async {
    if (credentials == null || closed) return;
    retry?.cancel();
    final previous = socket;
    socket = null;
    previous?.close();
    http?.close(force: true);
    status = '连接中';
    notifyListeners();
    try {
      http = pinnedClient(credentials!['fingerprint'] as String);
      final deviceName = credentials!['deviceName'] as String? ?? await deviceLabel();
      final connection = await WebSocket.connect(
        credentials!['url'] as String,
        headers: {
          'authorization': 'Bearer ${credentials!['token']}',
          'x-mobile-device-name': deviceName,
        },
        customClient: http,
      );
      socket = connection;
      connection.pingInterval = const Duration(seconds: 25);
      status = '已连接';
      retryAttempt = 0;
      notifyListeners();
      connection.listen(
        (raw) {
          final message = Map<String, dynamic>.from(jsonDecode(raw as String));
          if (['response', 'snapshot', 'error'].contains(message['kind']) &&
              message['id'] != null) {
            final waiter = pending.remove(message['id']);
            if (waiter != null && !waiter.isCompleted) {
              if (message['kind'] == 'error') {
                waiter.completeError(
                  RpcFailure(
                    message['payload']['code'] as String,
                    message['payload']['message'] as String,
                    message['id'] as String,
                  ),
                );
              } else {
                waiter.complete(message);
              }
            }
          } else {
            events.add(message);
          }
        },
        onDone: () {
          if (!identical(socket, connection)) return;
          if (connection.closeCode == 1008) {
            status = '设备已撤销，请重新配对';
            credentials = null;
            storage.delete(key: 'bridge');
            notifyListeners();
            failPending();
          } else {
            disconnected();
          }
        },
        onError: (_) {
          if (identical(socket, connection)) disconnected();
        },
      );
    } catch (error) {
      status = '连接失败：$error';
      notifyListeners();
      scheduleReconnect();
    }
  }

  void failPending() {
    for (final entry in pending.entries) {
      entry.value.completeError(
        RpcFailure('backend.result_unknown', '连接中断，操作结果待查询', entry.key),
      );
    }
    pending.clear();
  }

  void disconnected() {
    status = '连接中断';
    failPending();
    notifyListeners();
    scheduleReconnect();
  }

  void scheduleReconnect() {
    if (closed || credentials == null) return;
    retry?.cancel();
    final delay = [1, 2, 4, 8, 16, 30][retryAttempt.clamp(0, 5)];
    retryAttempt++;
    retry = Timer(Duration(seconds: delay), connect);
  }

  Future<Map<String, dynamic>> rpc(
    String method,
    Map<String, dynamic> payload, {
    String? backendId,
    int? generation,
    String kind = 'request',
    String? id,
  }) async {
    final requestId =
        id ?? '${DateTime.now().microsecondsSinceEpoch}-${++counter}';
    if (socket?.readyState != WebSocket.open) {
      throw RpcFailure('backend.disconnected', '电脑尚未连接', requestId);
    }
    final completer = Completer<Map<String, dynamic>>();
    pending[requestId] = completer;
    socket!.add(
      jsonEncode({
        'v': 1,
        'kind': kind,
        'id': requestId,
        'method': method,
        'payload': payload,
        'backendId': ?backendId,
        'backendGeneration': ?generation,
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 35));
    } on TimeoutException {
      throw RpcFailure('backend.result_unknown', '操作超时，请先查询结果', requestId);
    } finally {
      pending.remove(requestId);
    }
  }

  Future<List<int>> download(Map<String, dynamic> artifact) async {
    final url = Uri.parse(credentials!['url'] as String).replace(
      scheme: 'https',
      path: '/artifacts/${artifact['id']}',
      queryParameters: {
        'backendId': artifact['backendId'].toString(),
        'generation': artifact['generation'].toString(),
        'threadId': artifact['threadId'].toString(),
      },
    );
    final request = await http!.getUrl(url);
    request.headers.set('authorization', 'Bearer ${credentials!['token']}');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('附件下载失败 ${response.statusCode}');
    }
    return response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
  }

  Future<void> forget() async {
    credentials = null;
    retry?.cancel();
    socket?.close();
    await storage.delete(key: 'bridge');
    status = '未连接';
    notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    retry?.cancel();
    socket?.close();
    http?.close(force: true);
    events.close();
    super.dispose();
  }
}
