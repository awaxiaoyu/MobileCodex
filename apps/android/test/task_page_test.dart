import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_codex/bridge_client.dart';
import 'package:mobile_codex/main.dart';

class DesktopFixture extends BridgeClient {
  final calls = <String>[];
  List<Map<String, dynamic>> fixtureProjects = [
    {'projectId': 'workspace', 'label': 'Workspace', 'branch': 'main'},
  ];
  List<Map<String, dynamic>> fixtureThreads = [];
  Map<String, dynamic>? firstTurn;
  Map<String, dynamic> fixtureSnapshot = {
    'id': 'snapshot-chat',
    'title': 'Snapshot chat',
    'turns': [
      {
        'id': 'turn-1',
        'items': [
          {'id': 'visible', 'type': 'userMessage', 'text': 'Visible request'},
          {'id': 'empty', 'type': 'agentMessage', 'text': ''},
          {
            'id': 'tool',
            'type': 'commandExecution',
            'aggregatedOutput': 'Hidden tool output',
          },
        ],
      },
    ],
  };

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
      'bridge.project.list' => {'projects': fixtureProjects},
      'bridge.thread.list' => {'threads': fixtureThreads},
      'bridge.model.list' => {
        'data': [
          {'model': 'test-model', 'isDefault': true},
          {'model': 'second-model'},
        ],
      },
      'bridge.thread.create' => {
        'thread': {'id': 'new-thread', 'title': '', 'turns': <dynamic>[]},
      },
      'bridge.turn.start' => {
        'turn': {'id': 'first-turn', 'status': 'inProgress'},
      },
      'bridge.thread.resume' => {},
      'bridge.snapshot.get' => {
        'thread': fixtureSnapshot,
        'streamId': 'snapshot-stream',
        'seq': 0,
        'approvals': <dynamic>[],
      },
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
  await tester.tap(find.byKey(const ValueKey('new-chat')));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  testWidgets(
    'new chat opens without resume/read and can start its first turn',
    (tester) async {
      final client = await openNewChat(tester);
      expect(find.text('Workspace/New chat'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        client.calls.where((m) => m == 'bridge.thread.create'),
        hasLength(1),
      );
      expect(client.calls, isNot(contains('bridge.thread.resume')));
      expect(client.calls, isNot(contains('bridge.snapshot.get')));

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(client.calls, isNot(contains('bridge.snapshot.get')));
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'first message');
      await tester.tap(find.byTooltip('Send'));
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

  testWidgets('composer exposes every model advertised by the bridge', (
    tester,
  ) async {
    await openNewChat(tester);
    await tester.tap(find.byKey(const ValueKey('model-select')));
    await tester.pumpAndSettle();
    expect(find.text('second-model'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer shows project context and fits a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openNewChat(tester);

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-select')), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
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
        {
          'id': 'alpha-chat',
          'title': 'Alpha chat',
          'preview': 'Alpha request',
          'projectId': 'alpha',
        },
        {
          'id': 'beta-chat',
          'title': 'Beta chat',
          'preview': 'Beta request',
          'projectId': 'beta',
        },
        {
          'id': 'recent-chat',
          'title': 'Recent chat',
          'preview': 'Recent request',
        },
        {
          'id': 'pinned-chat',
          'title': 'Pinned chat',
          'preview': 'Pinned request',
          'projectId': 'beta',
          'pinned': true,
        },
        {
          'id': 'empty-chat',
          'title': 'Empty chat',
          'turns': [
            {
              'items': [
                {'type': 'agentMessage', 'text': ''},
                {'type': 'commandExecution', 'aggregatedOutput': 'hidden'},
              ],
            },
          ],
        },
      ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('PROJECTS'), findsOneWidget);
    expect(find.text('CONVERSATIONS'), findsOneWidget);
    expect(find.text('Recent chat'), findsOneWidget);
    expect(find.text('Pinned chat'), findsOneWidget);
    expect(find.text('Empty chat'), findsNothing);
    expect(find.text('Alpha chat'), findsNothing);
    expect(find.textContaining('now'), findsNothing);

    await tester.tap(find.byKey(const PageStorageKey('project-alpha')));
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

  testWidgets('timeline omits empty rows and synthetic now timestamps', (
    tester,
  ) async {
    final fixture = DesktopFixture()
      ..fixtureThreads = [
        {
          'id': 'snapshot-chat',
          'title': 'Snapshot chat',
          'preview': 'Visible request',
        },
      ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snapshot chat'));
    await tester.pumpAndSettle();

    expect(find.text('Visible request'), findsOneWidget);
    expect(find.text('Hidden tool output'), findsNothing);
    expect(find.textContaining('now'), findsNothing);
    expect(find.text('Codex · now'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed turns show only the final answer and can expand', (
    tester,
  ) async {
    final fixture = DesktopFixture()
      ..fixtureThreads = [
        {
          'id': 'snapshot-chat',
          'title': 'Snapshot chat',
          'preview': 'Visible request',
        },
      ]
      ..fixtureSnapshot = {
        'id': 'snapshot-chat',
        'title': 'Snapshot chat',
        'turns': [
          {
            'id': 'completed-turn',
            'status': 'completed',
            'items': [
              {
                'id': 'request',
                'type': 'userMessage',
                'text': 'Original request',
              },
              {'id': 'plan', 'type': 'plan', 'text': 'Intermediate plan'},
              {'id': 'answer', 'type': 'agentMessage', 'text': 'Final answer'},
            ],
          },
        ],
      };
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snapshot chat'));
    await tester.pumpAndSettle();

    expect(find.text('Original request'), findsNothing);
    expect(find.text('Intermediate plan'), findsNothing);
    expect(find.text('Final answer'), findsOneWidget);
    expect(find.text('Final response'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-turn-completed-turn')));
    await tester.pumpAndSettle();
    expect(find.text('Original request'), findsOneWidget);
    expect(find.text('Intermediate plan'), findsNothing);
    expect(find.text('Hide earlier messages'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer shell has no border and preferences are actionable', (
    tester,
  ) async {
    final fixture = DesktopFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();

    final composer = tester.widget<Container>(
      find.byKey(const ValueKey('composer-shell')),
    );
    expect(composer.decoration, isA<BoxDecoration>());
    expect((composer.decoration! as BoxDecoration).border, isNull);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-appearance')));
    await tester.pumpAndSettle();
    expect(find.text('Show reasoning summaries'), findsOneWidget);
    expect(find.text('Collapse completed turns'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings opens as a full page with supported sections only', (
    tester,
  ) async {
    final fixture = DesktopFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Archived chats'), findsNothing);
    expect(find.text('Plugins'), findsNothing);
    expect(find.text('Computer use'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-voice')));
    await tester.pumpAndSettle();
    expect(find.text('Voice input'), findsOneWidget);
    expect(find.text('Dictation language'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-storage')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Storage'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty titles without message content are omitted from chats', (
    tester,
  ) async {
    final fixture = DesktopFixture()
      ..fixtureThreads = [
        {'id': 'empty', 'title': 'Generated title only'},
      ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Generated title only'), findsNothing);
    expect(find.text('No conversations'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('thread summaries with empty turns remain visible', (
    tester,
  ) async {
    final fixture = DesktopFixture()
      ..fixtureThreads = [
        {
          'id': 'summary-chat',
          'title': 'Saved chat',
          'preview': 'Saved request',
          'turns': <dynamic>[],
          'status': 'idle',
          'updatedAt': '2026-10-18T05:00:00Z',
        },
      ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(MaterialApp(home: TaskPage(client: fixture)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Saved chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
