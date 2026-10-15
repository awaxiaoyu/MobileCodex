import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_codex/bridge_client.dart';
import 'package:mobile_codex/main.dart';

class DesktopFixture extends BridgeClient {
  final calls = <String>[];
  List<Map<String, dynamic>> fixtureProjects = [
    {'projectId': 'workspace', 'label': 'Workspace'},
  ];
  List<Map<String, dynamic>> fixtureThreads = [];
  Map<String, dynamic>? firstTurn;

  @override
  Future<void> restore() async {
    status = '已连接';
    events.add({'method': 'event.connection.ready'});
  }

  @override
  Future<Map<String, dynamic>> rpc(
    String method,
    Map<String, dynamic> payload, {
    String? backendId,
    int? generation,
    String kind = 'request',
    String? id,
  }) async {
    calls.add(method);
    final data = switch (method) {
      'bridge.backends.list' => {
        'backends': [
          {
            'id': 'desktop',
            'kind': 'desktop-shared',
            'status': 'connected',
            'generation': 1,
          },
        ],
      },
      'bridge.project.list' => {
        'projects': fixtureProjects,
      },
      'bridge.thread.list' => {'threads': fixtureThreads},
      'bridge.model.list' => {
        'data': [
          {'model': 'test-model', 'isDefault': true},
        ],
      },
      'bridge.thread.create' => {
        'thread': {'id': 'new-thread', 'title': '', 'turns': <dynamic>[]},
      },
      'bridge.turn.start' => {
        'turn': {'id': 'first-turn', 'status': 'inProgress'},
      },
      // Desktop cannot read a new thread before its first turn.
      'bridge.thread.resume' || 'bridge.snapshot.get' => throw StateError(
        'A new thread has no rollout yet',
      ),
      _ => throw StateError('Unexpected method $method'),
    };
    if (method == 'bridge.turn.start') firstTurn = Map.of(payload);
    return {'payload': data};
  }
}

Future<DesktopFixture> openNewChat(
  WidgetTester tester, {
  DesktopFixture? fixture,
}) async {
  final client = fixture ?? DesktopFixture();
  addTearDown(client.dispose);
  await tester.pumpWidget(MaterialApp(home: TaskPage(client: client)));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('新建聊天'));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  testWidgets(
    'new chat opens without resume/read and can start its first turn',
    (tester) async {
      final client = await openNewChat(tester);
      expect(find.text('新聊天'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        client.calls.where((m) => m == 'bridge.thread.create'),
        hasLength(1),
      );
      expect(client.calls, isNot(contains('bridge.thread.resume')));
      expect(client.calls, isNot(contains('bridge.snapshot.get')));

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(client.calls, isNot(contains('bridge.snapshot.get')));
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'first message');
      await tester.tap(find.byTooltip('发送'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.firstTurn?['threadId'], 'new-thread');
      expect(client.firstTurn?['input'][0]['text'], 'first message');
      expect(client.calls, isNot(contains('bridge.turn.steer')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('burst deltas are batched without losing message content', (
    tester,
  ) async {
    final client = await openNewChat(tester);
    for (var i = 1; i <= 100; i++) {
      client.events.add({
        'method': 'event.item.delta',
        'backendId': 'desktop',
        'threadId': 'new-thread',
        'streamId': 'stream',
        'seq': i,
        'payload': {'turnId': 'turn', 'itemId': 'message', 'delta': 'x'},
      });
    }
    await tester.pump();
    expect(find.text('x' * 100), findsNothing);
    await tester.pump(const Duration(milliseconds: 34));
    expect(find.text('x' * 100), findsOneWidget);
    expect(client.calls, isNot(contains('bridge.snapshot.get')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('session menu groups projects, recent chats and pinned chats', (
    tester,
  ) async {
    final fixture = DesktopFixture()
      ..fixtureProjects = [
        {'projectId': 'alpha', 'label': 'Project Alpha'},
        {'projectId': 'beta', 'label': 'Project Beta'},
      ]
      ..fixtureThreads = [
        {'id': 'alpha-chat', 'title': 'Alpha chat', 'projectId': 'alpha'},
        {'id': 'beta-chat', 'title': 'Beta chat', 'projectId': 'beta'},
        {'id': 'recent-chat', 'title': 'Recent chat'},
      ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('Recent chat'), findsOneWidget);
    expect(find.text('Alpha chat'), findsNothing);

    await tester.tap(find.text('Project Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha chat'), findsOneWidget);
    expect(find.text('Beta chat'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('thread-actions-alpha-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pin-thread-alpha-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-alpha-chat')), findsOneWidget);
    expect(find.text('Alpha chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
