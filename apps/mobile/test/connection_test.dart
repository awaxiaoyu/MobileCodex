import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_codex/bridge_client.dart';
import 'package:mobile_codex/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  testWidgets('unpaired mobile displays connection and task entry', (tester) async {
    await tester.pumpWidget(const MobileCodexApp()); await tester.pump();
    expect(find.text('Mobile Codex'), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-menu')), findsOneWidget);
  });

  testWidgets('computer pairing offers QR scanning and manual entry', (tester) async {
    await tester.pumpWidget(const MobileCodexApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connected computer'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('scan-pairing-code')), findsOneWidget);
    expect(find.text('Paste the pairing information from your computer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('mobile pins certificate, pairs through HTTPS, calls WSS and handles revocation', () async {
    // testWidgets installs a fake HTTP client. Use a plain Dart test so this
    // checks the real native HttpClient against the Node Bridge transport.
    HttpOverrides.global = null;
    final root = await Directory.systemTemp.createTemp('mobile-dart-');
    final generated = await Process.run('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', '${root.path}/key.pem', '-out', '${root.path}/cert.pem', '-days', '1', '-subj', '/CN=localhost']);
    expect(generated.exitCode, 0);
    final process = await Process.start('node', ['../../tests/fixtures/mobile-server.mjs', root.path]);
    final client = BridgeClient();
    try {
      final lines = process.stdout.transform(utf8.decoder).transform(const LineSplitter());
      final pairing = jsonDecode(await lines.first) as Map<String, dynamic>;
      final wrong = {...pairing, 'fingerprint': List.filled(64, '0').join()};
      await expectLater(client.pair(jsonEncode(wrong), 'wrong-pin'), throwsA(anything));
      final ready = Completer<void>();
      final subscription = client.events.stream.listen((e) { if (e['method'] == 'event.connection.ready' && !ready.isCompleted) { ready.complete(); } });
      await client.pair(jsonEncode(pairing), 'test-phone'); await ready.future.timeout(const Duration(seconds: 5));
      final result = await client.rpc('bridge.backends.list', {});
      expect(result['payload']['backends'], isEmpty);
      expect(client.credentials!.containsKey('secret'), false);
      process.stdin.writeln('revoke');
      for (var i = 0; i < 50 && client.credentials != null; i++) { await Future<void>.delayed(const Duration(milliseconds: 100)); }
      expect(client.credentials, isNull); expect(client.status, contains('撤销'));
      await subscription.cancel();
    } finally {
      client.dispose(); process.stdin.writeln('close'); await process.stdin.close();
      process.kill(); await process.exitCode; await root.delete(recursive: true);
    }
  });
}
