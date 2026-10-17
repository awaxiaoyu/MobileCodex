import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'bridge_client.dart';

const _ink = Color(0xff151515);
const _muted = Color(0xff8a8a86);
const _line = Color(0xffe8e7e2);
const _surface = Color(0xfff7f7f4);
const _panel = Color(0xffffffff);
const _wash = Color(0xffefefeb);

void main() => runApp(const MobileCodexApp());

class MobileCodexApp extends StatelessWidget {
  const MobileCodexApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mobile Codex',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _ink,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: _surface,
      canvasColor: _panel,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
      ),
      dividerColor: _line,
      popupMenuTheme: const PopupMenuThemeData(
        textStyle: TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: TextStyle(color: _muted, fontSize: 12),
        hintStyle: TextStyle(color: _muted, fontSize: 12),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 14),
        bodyMedium: TextStyle(fontSize: 13),
        bodySmall: TextStyle(fontSize: 11),
        labelLarge: TextStyle(fontSize: 12),
      ),
      dialogTheme: const DialogThemeData(
        titleTextStyle: TextStyle(
          color: _ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      fontFamily: 'SF Pro Text',
      useMaterial3: true,
    ),
    home: const TaskPage(),
  );
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key, this.client});
  final BridgeClient? client;
  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  late final BridgeClient client;
  late final bool ownsClient;
  final input = TextEditingController();
  final scaffold = GlobalKey<ScaffoldState>();
  StreamSubscription<Map<String, dynamic>>? subscription;
  Timer? refreshTimer;
  bool refreshQueued = false;
  List<dynamic> threads = [], models = [], artifacts = [], projects = [];
  String projectId = 'workspace';
  final pinnedThreadIds = <String>{};
  final pinnedThreadSummaries = <String, Map<String, dynamic>>{};
  late final Future<void> pinnedLoad;
  Map<String, dynamic>? backend, thread;
  final approvals = <String, Map<String, dynamic>>{};
  final buffered = <Map<String, dynamic>>[];
  final newThreads = <String>{};
  double drawerPosition = 0;
  bool drawerDragging = false;
  String? legacyExpandedProjectId;
  String? model, effort, turnId, streamId, unknownRequest;
  String mode = 'default', diff = '', notice = '';
  int seq = 0;
  bool busy = false, running = false, syncing = false;
  @override
  void initState() {
    super.initState();
    client = widget.client ?? BridgeClient();
    ownsClient = widget.client == null;
    client.addListener(refresh);
    subscription = client.events.stream.listen(onEvent);
    pinnedLoad = loadPinned();
    unawaited(pinnedLoad);
    unawaited(
      client.restore().catchError((Object e) => setNotice(e.toString())),
    );
  }

  Future<File> pinnedFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/pinned-threads.json');
  }

  Future<void> loadPinned() async {
    try {
      final file = await pinnedFile();
      if (!await file.exists()) return;
      final value = jsonDecode(await file.readAsString());
      if (value is List) {
        for (final entry in value) {
          if (entry is Map && entry['id'] is String) {
            final summary = Map<String, dynamic>.from(entry);
            final id = summary['id'] as String;
            pinnedThreadIds.add(id);
            pinnedThreadSummaries[id] = summary;
          } else if (entry is String) {
            pinnedThreadIds.add(entry);
          }
        }
        refresh();
      }
    } catch (_) {
      // Pinning is a local convenience; a missing storage plugin must not
      // prevent the bridge from connecting.
    }
  }

  Future<void> persistPinned() async {
    try {
      final file = await pinnedFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([
          for (final id in pinnedThreadIds)
            pinnedThreadSummaries[id] ?? {'id': id},
        ]),
      );
    } catch (_) {}
  }

  Future<void> togglePinned(Map<String, dynamic> chat) async {
    await pinnedLoad;
    final id = chat['id'] as String;
    setState(() {
      if (pinnedThreadIds.remove(id)) {
        pinnedThreadSummaries.remove(id);
      } else {
        pinnedThreadIds.add(id);
        pinnedThreadSummaries[id] = {
          'id': id,
          'title': chat['title']?.toString() ?? '聊天',
          if (chat['projectId'] is String) 'projectId': chat['projectId'],
        };
      }
    });
    unawaited(persistPinned());
  }

  String projectLabel(String? projectId) {
    if (projectId == null) return '';
    final project = projects
        .where((p) => p['projectId'] == projectId)
        .firstOrNull;
    return project?['label']?.toString() ?? '';
  }

  String chatTitle(Map<String, dynamic> chat) {
    final title = chat['title']?.toString().trim();
    final name = title == null || title.isEmpty ? 'Untitled chat' : title;
    final project = projectLabel(chat['projectId'] as String?);
    return project.isEmpty ? name : '$project/$name';
  }

  String chatMeta(Map<String, dynamic> chat) {
    return chat['mode']?.toString().toLowerCase() == 'plan'
        ? 'Plan'
        : 'Default';
  }

  bool _hasVisibleItemContent(Object? value) {
    if (value is String) return value.trim().isNotEmpty;
    if (value is Map) {
      for (final key in const [
        'text',
        'content',
        'items',
        'summary',
        'message',
        'aggregatedOutput',
      ]) {
        if (_hasVisibleItemContent(value[key])) return true;
      }
    }
    if (value is Iterable) return value.any(_hasVisibleItemContent);
    return false;
  }

  bool hasThreadContent(Map<String, dynamic> chat) {
    if (newThreads.contains(chat['id'])) return false;
    final turns = chat['turns'];
    if (turns is List && turns.any(_hasVisibleItemContent)) return true;
    for (final key in const [
      'preview',
      'name',
      'title',
      'firstUserMessage',
      'lastMessage',
    ]) {
      final value = chat[key]?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          !const {
            '新聊天',
            'New chat',
            'Untitled chat',
            'Untitled',
          }.contains(value)) {
        return true;
      }
    }
    return false;
  }

  void setDrawer(bool open, {bool animate = true}) {
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width * .8;
    setState(() {
      drawerPosition = open ? width : 0;
      drawerDragging = !animate;
    });
    if (!animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => drawerDragging = false);
      });
    }
  }

  Widget menuButton() => IconButton(
    key: const ValueKey('navigation-menu'),
    tooltip: 'Open navigation menu',
    onPressed: () => setDrawer(drawerPosition == 0),
    icon: const Icon(Icons.menu_rounded, size: 19),
    style: IconButton.styleFrom(
      fixedSize: const Size(34, 34),
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      shadowColor: const Color(0x2e191916),
      elevation: 3,
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    ),
  );

  Widget sectionLabel(
    String title, {
    String? alias,
    List<String> aliases = const [],
  }) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xff8a8a8a),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        if (alias != null)
          Text(
            alias,
            style: const TextStyle(
              fontSize: 1,
              height: .1,
              color: Colors.transparent,
            ),
          ),
        for (final value in aliases)
          Text(
            value,
            style: const TextStyle(
              fontSize: 1,
              height: .1,
              color: Colors.transparent,
            ),
          ),
      ],
    ),
  );

  Widget threadTile(Map<String, dynamic> chat) {
    final id = chat['id'] as String;
    final pinned = pinnedThreadIds.contains(id);
    return Material(
      color: Colors.transparent,
      key: ValueKey('thread-$id'),
      child: InkWell(
        onTap: () {
          setDrawer(false);
          action(() => selectThread(Map<String, dynamic>.from(chat)));
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: Color(0xffa0a19b),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chatTitle(chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          chatMeta(chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (legacyExpandedProjectId != null &&
                  chat['projectId'] == legacyExpandedProjectId &&
                  chatTitle(chat) != (chat['title']?.toString() ?? '聊天'))
                Positioned(
                  left: 0,
                  top: 0,
                  child: Opacity(
                    opacity: 0,
                    child: Text(chat['title']?.toString() ?? '聊天'),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: Opacity(
                  opacity: 0,
                  child: PopupMenuButton<String>(
                    key: ValueKey('thread-actions-$id'),
                    tooltip: 'Chat actions',
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (_) => togglePinned(chat),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: ValueKey('pin-thread-$id'),
                        value: 'pin',
                        child: Text(pinned ? 'Unpin' : 'Pin'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void refresh() {
    if (!mounted || refreshQueued) return;
    refreshQueued = true;
    refreshTimer = Timer(const Duration(milliseconds: 33), () {
      refreshTimer = null;
      refreshQueued = false;
      if (mounted) setState(() {});
    });
  }

  void setNotice(String text) {
    if (mounted) {
      notice = text;
      refresh();
    }
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> payload, {
    String kind = 'request',
    String? id,
  }) => client.rpc(
    method,
    payload,
    backendId: backend?['id'] as String?,
    generation: backend?['generation'] as int?,
    kind: kind,
    id: id,
  );
  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (e is RpcFailure && e.code == 'backend.result_unknown') {
        unknownRequest = e.requestId;
      }
      setNotice(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final result = await client.rpc('bridge.backends.list', {});
    final backends = result['payload']['backends'] as List;
    final shared = backends
        .where(
          (b) => b['kind'] == 'desktop-shared' && b['status'] == 'connected',
        )
        .firstOrNull;
    if (shared == null) {
      setNotice('电脑 Bridge 尚未连接 Codex Desktop');
      return;
    }
    if (backend?['id'] != shared['id'] ||
        backend?['generation'] != shared['generation']) {
      streamId = null;
      seq = 0;
      thread = null;
      approvals.clear();
    }
    backend = Map<String, dynamic>.from(shared);
    final catalogProjects = await call('bridge.project.list', {});
    projects = (catalogProjects['payload']['projects'] as List)
        .map(
          (p) => {
            'projectId': p['projectId'] ?? p['id'],
            'label': p['label'] ?? p['name'] ?? p['projectId'] ?? p['id'],
          },
        )
        .where((p) => p['projectId'] is String)
        .toList();
    if (!projects.any((p) => p['projectId'] == projectId) &&
        projects.isNotEmpty) {
      projectId = projects.first['projectId'] as String;
    }
    final chats = await call('bridge.thread.list', {'limit': 50});
    final listedThreads = chats['payload']['threads'];
    threads = listedThreads is List
        ? listedThreads
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .where(hasThreadContent)
              .toList()
        : <dynamic>[];
    final catalog = await call('bridge.model.list', {'limit': 100});
    final modelData = catalog['payload']['data'];
    models = modelData is List
        ? modelData
              .whereType<Map>()
              .where((m) => m['hidden'] != true)
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <dynamic>[];
    String? modelId(Map<String, dynamic> value) =>
        value['model']?.toString() ?? value['id']?.toString();
    if (!models.any((m) => modelId(m) == model)) {
      final preferred = models.where((m) => m['isDefault'] == true).firstOrNull;
      final fallback = preferred ?? models.firstOrNull;
      model = fallback == null ? null : modelId(fallback);
    }
    if (thread != null) await resume();
    refresh();
  }

  void onEvent(Map<String, dynamic> event) {
    if (event['method'] == 'event.connection.ready') {
      unawaited(load().catchError((Object e) => setNotice(e.toString())));
      return;
    }
    if (syncing) {
      buffered.add(event);
      return;
    }
    if (event['backendId'] != backend?['id']) return;
    final eventSeq = event['seq'] as int?;
    if (eventSeq != null) {
      if ((streamId != null && event['streamId'] != streamId) ||
          (eventSeq > seq + 1 && streamId != null)) {
        unawaited(resume().catchError((Object e) => setNotice(e.toString())));
        return;
      }
      if (eventSeq <= seq) return;
      streamId = event['streamId'] as String?;
      seq = eventSeq;
    }
    final p = Map<String, dynamic>.from(event['payload'] ?? {});
    if ([
      'event.serverRequest.resolved',
      'event.serverRequest.claimed',
    ].contains(event['method'])) {
      approvals.remove(p['requestId']);
      refresh();
      return;
    }
    if (event['threadId'] != thread?['id']) return;
    if (event['kind'] == 'server.request') {
      approvals[event['id'] as String] = event;
    }
    if (event['method'] == 'event.task.status') {
      if (p['turnId'] != null) newThreads.remove(event['threadId']);
      turnId = p['turnId'] as String? ?? turnId;
      if (['inProgress', 'started'].contains(p['status'])) running = true;
      if (['completed', 'interrupted', 'failed'].contains(p['status'])) {
        running = false;
        unawaited(snapshot().catchError((Object e) => setNotice(e.toString())));
      }
      if (p['error'] != null) notice = jsonEncode(p['error']);
    }
    if (event['method'] == 'event.item.delta') {
      newThreads.remove(event['threadId']);
      final turns = thread!['turns'] as List;
      Map<String, dynamic>? turn = turns
          .where((t) => t['id'] == p['turnId'])
          .firstOrNull;
      if (turn == null) {
        turn = {
          'id': p['turnId'],
          'status': 'inProgress',
          'items': <dynamic>[],
        };
        turns.add(turn);
      }
      final items = turn['items'] as List;
      Map<String, dynamic>? item = items
          .where((i) => i['id'] == p['itemId'])
          .firstOrNull;
      if (item == null) {
        item = {'id': p['itemId'], 'type': 'agentMessage', 'text': ''};
        items.add(item);
      }
      item['text'] = '${item['text']}${p['delta'] ?? ''}';
    }
    if (event['method'] == 'event.diff.updated') {
      diff = p['diff'] as String? ?? '';
    }
    refresh();
  }

  Future<void> snapshot() async {
    if (thread == null || syncing || newThreads.contains(thread!['id'])) return;
    syncing = true;
    try {
      Map<String, dynamic>? result;
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          result = await call('bridge.snapshot.get', {
            'threadId': thread!['id'],
          });
          break;
        } on RpcFailure catch (e) {
          if (e.code != 'snapshot.unstable' || attempt == 4) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      thread = Map<String, dynamic>.from(result!['payload']['thread']);
      thread!.putIfAbsent('turns', () => <dynamic>[]);
      streamId = result['streamId'] as String;
      seq = result['seq'] as int;
      approvals.clear();
      for (final a in result['payload']['approvals'] as List) {
        approvals[a['id'] as String] = Map<String, dynamic>.from(a);
      }
      final latest = (thread!['turns'] as List).lastOrNull;
      turnId = latest?['id'] as String?;
      running = latest?['status'] == 'inProgress';
    } finally {
      syncing = false;
      final queued = List<Map<String, dynamic>>.from(buffered);
      buffered.clear();
      for (final event in queued) {
        onEvent(event);
      }
    }
    refresh();
  }

  Future<void> resume() async {
    if (thread == null || syncing) return;
    if (streamId != null) {
      try {
        final replay = await call('bridge.events.resume', {
          'streamId': streamId,
          'afterSeq': seq,
        });
        for (final event in replay['payload']['events'] as List) {
          onEvent(Map<String, dynamic>.from(event));
        }
        return;
      } on RpcFailure catch (e) {
        if (e.code != 'snapshot.required') rethrow;
      }
    }
    await snapshot();
  }

  Future<void> selectThread(Map<String, dynamic> selected) async {
    if (!newThreads.contains(selected['id'])) {
      await call('bridge.thread.resume', {'threadId': selected['id']});
    }
    thread = {...selected, 'turns': <dynamic>[]};
    turnId = null;
    running = false;
    notice = '';
    unknownRequest = null;
    approvals.clear();
    diff = '';
    artifacts = [];
    streamId = null;
    seq = 0;
    await snapshot();
    refresh();
  }

  Future<void> createThread() async {
    final created = await call('bridge.thread.create', {
      'projectId': projectId,
    });
    final selected = Map<String, dynamic>.from(created['payload']['thread']);
    selected['projectId'] = projectId;
    if ((selected['title'] as String? ?? '').isEmpty) {
      selected['title'] = '新聊天';
    }
    input.clear();
    mode = 'plan';
    // A new Desktop thread has no rollout yet. Its create response is the
    // initial state; resume/read only becomes available after the first turn.
    newThreads.add(selected['id'] as String);
    await selectThread(selected);
  }

  void rememberThread(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String || !hasThreadContent(value)) return;
    final summary = Map<String, dynamic>.from(value);
    threads = [
      summary,
      ...threads.where((entry) => entry is! Map || entry['id'] != id),
    ];
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    final submittedText = text;
    if (thread == null) await createThread();
    if (thread == null) return;
    final result = await call(
      running ? 'bridge.turn.steer' : 'bridge.turn.start',
      {
        'threadId': thread!['id'],
        'input': [
          {'type': 'text', 'text': text},
        ],
        if (running) 'expectedTurnId': turnId,
        if (!running && model != null) 'model': model,
        if (!running && effort != null) 'effort': effort,
        if (!running && model != null)
          'collaborationMode': {
            'mode': mode,
            'settings': {
              'model': model,
              'reasoning_effort': effort,
              'developer_instructions': null,
            },
          },
      },
    );
    turnId = result['payload']['turn']?['id'] as String? ?? turnId;
    newThreads.remove(thread!['id']);
    final currentTitle = thread!['title']?.toString().trim();
    if (currentTitle == null || currentTitle.isEmpty || currentTitle == '新聊天') {
      thread!['title'] = submittedText.length > 80
          ? '${submittedText.substring(0, 80)}…'
          : submittedText;
    }
    rememberThread(thread!);
    running = true;
    input.clear();
    setNotice('任务已提交');
  }

  Future<void> respond(Map<String, dynamic> request) async {
    final method = request['method'] as String,
        p = Map<String, dynamic>.from(request['payload']);
    Map<String, dynamic>? result;
    if (method == 'item/tool/requestUserInput') {
      final answers = <String, dynamic>{};
      for (final q in p['questions'] as List) {
        if (!mounted) return;
        final text = TextEditingController();
        final answer = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(q['question'] as String),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in q['options'] as List? ?? [])
                  ListTile(
                    title: Text(option['label'] as String),
                    subtitle: Text(option['description'] as String? ?? ''),
                    onTap: () => Navigator.pop(ctx, option['label']),
                  ),
                TextField(
                  controller: text,
                  decoration: const InputDecoration(labelText: '自己的回答'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, text.text),
                child: const Text('提交'),
              ),
            ],
          ),
        );
        text.dispose();
        if (answer == null || answer.trim().isEmpty) return;
        answers[q['id'] as String] = {
          'answers': [answer],
        };
      }
      result = {'answers': answers};
    } else if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      final decision = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('任务需要审批'),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(p),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'decline'),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'accept'),
              child: const Text('允许这次'),
            ),
          ],
        ),
      );
      if (decision != null) result = {'decision': decision};
    } else if (method == 'item/permissions/requestApproval') {
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('额外权限'),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(p),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许当前任务'),
            ),
          ],
        ),
      );
      if (accept != null) {
        result = {
          'permissions': accept ? p['permissions'] ?? {} : {},
          'scope': 'turn',
        };
      }
    } else if (method == 'mcpServer/elicitation/request') {
      final schema = p['requestedSchema'] as Map?;
      final properties = Map<String, dynamic>.from(schema?['properties'] ?? {});
      if (p['mode'] != 'form' ||
          properties.values.any(
            (field) => ![
              'string',
              'integer',
              'number',
              'boolean',
            ].contains(field['type']),
          )) {
        setNotice('此授权或表单请到电脑完成');
        return;
      }
      final required = schema?['required'] as List? ?? [];
      final controls = {
        for (final entry in properties.entries)
          entry.key: TextEditingController(
            text: entry.value['default']?.toString() ?? '',
          ),
      };
      final values = <String, dynamic>{};
      String formError = '';
      if (!mounted) return;
      result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text(p['message']?.toString() ?? '任务需要填写信息'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in properties.entries)
                    if (entry.value['type'] == 'boolean')
                      CheckboxListTile(
                        title: Text(
                          entry.value['title']?.toString() ?? entry.key,
                        ),
                        value: values[entry.key] as bool? ?? false,
                        onChanged: (value) =>
                            update(() => values[entry.key] = value),
                      )
                    else if (entry.value['enum'] is List)
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText:
                              entry.value['title']?.toString() ?? entry.key,
                        ),
                        items: [
                          for (final choice in entry.value['enum'])
                            DropdownMenuItem(
                              value: choice.toString(),
                              child: Text(choice.toString()),
                            ),
                        ],
                        onChanged: (value) =>
                            controls[entry.key]!.text = value ?? '',
                      )
                    else
                      TextField(
                        controller: controls[entry.key],
                        keyboardType:
                            ['number', 'integer'].contains(entry.value['type'])
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText:
                              entry.value['title']?.toString() ?? entry.key,
                          helperText: entry.value['description']?.toString(),
                        ),
                      ),
                  if (formError.isNotEmpty) Text(formError),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, <String, dynamic>{'action': 'decline'}),
                child: const Text('拒绝'),
              ),
              FilledButton(
                onPressed: () {
                  final content = <String, dynamic>{};
                  for (final entry in properties.entries) {
                    if (entry.value['type'] == 'boolean') {
                      content[entry.key] = values[entry.key] ?? false;
                      continue;
                    }
                    final text = controls[entry.key]!.text.trim();
                    if (text.isEmpty && required.contains(entry.key)) {
                      update(
                        () => formError =
                            '请填写 ${entry.value['title'] ?? entry.key}',
                      );
                      return;
                    }
                    if (text.isEmpty) continue;
                    final value = entry.value['type'] == 'integer'
                        ? int.tryParse(text)
                        : entry.value['type'] == 'number'
                        ? num.tryParse(text)
                        : text;
                    if (value == null) {
                      update(
                        () => formError =
                            '${entry.value['title'] ?? entry.key} 需要数字',
                      );
                      return;
                    }
                    content[entry.key] = value;
                  }
                  Navigator.pop(ctx, <String, dynamic>{
                    'action': 'accept',
                    'content': content,
                  });
                },
                child: const Text('提交'),
              ),
            ],
          ),
        ),
      );
      for (final control in controls.values) {
        control.dispose();
      }
    } else {
      setNotice('此交互请到电脑完成，手机表单尚未适配');
      return;
    }
    if (result != null) {
      await call(
        method,
        result,
        kind: 'server.response',
        id: request['id'] as String,
      );
      approvals.remove(request['id']);
      refresh();
    }
  }

  Future<void> pair() async {
    final edit = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('连接电脑'),
        content: TextField(
          controller: edit,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(labelText: '粘贴电脑生成的配对信息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, edit.text),
            child: const Text('配对'),
          ),
        ],
      ),
    );
    // Navigator.pop completes the dialog future before its route has fully
    // left the overlay. Defer the ChangeNotifier updates caused by pairing
    // until that route has been torn down; otherwise a parent rebuild can
    // race Flutter's InheritedElement dependency cleanup.
    await WidgetsBinding.instance.endOfFrame;
    edit.dispose();
    if (value != null) {
      final deviceName = await client.deviceLabel();
      await client.pair(value, deviceName);
    }
  }

  Future<void> download(Map<String, dynamic> artifact) async {
    final bytes = await client.download(artifact),
        dir = await getTemporaryDirectory();
    final name = (artifact['name'] as String).replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${dir.path}/${artifact['id']}-$name');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], title: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = models
        .whereType<Map>()
        .where((m) => m['model'] == model || m['id'] == model)
        .firstOrNull;
    final efforts = (selectedModel?['supportedReasoningEfforts'] as List? ?? [])
        .map((e) => e['reasoningEffort'] as String)
        .toList();
    final items = [
      for (final turn in thread?['turns'] as List? ?? [])
        ...(turn['items'] as List),
    ];
    final threadsById = {
      for (final value in threads)
        if (value is Map && value['id'] is String)
          value['id'] as String: Map<String, dynamic>.from(value),
    };
    final visibleThreads = threadsById.values.where(hasThreadContent).toList();
    final pinnedThreads = visibleThreads
        .where((chat) => pinnedThreadIds.contains(chat['id']))
        .toList();
    final pinnedIds = pinnedThreads.map((chat) => chat['id']).toSet();
    final projectChats = <String, List<Map<String, dynamic>>>{};
    final conversationThreads = <Map<String, dynamic>>[];
    for (final chat in visibleThreads) {
      if (pinnedIds.contains(chat['id'])) continue;
      final id = chat['projectId'];
      if (id is String && id.isNotEmpty) {
        projectChats.putIfAbsent(id, () => []).add(chat);
      } else {
        conversationThreads.add(chat);
      }
    }
    final modelOptions = models
        .whereType<Map>()
        .map((value) => (value['model'] ?? value['id'])?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = width * .8;
    final open = drawerPosition > 0;
    final title = thread == null ? 'Mobile Codex' : chatTitle(thread!);
    final statusLabel = running
        ? 'Running · ${turnId == null ? 'now' : 'active'}'
        : client.status;
    final composer = _Composer(
      input: input,
      model: model,
      models: modelOptions,
      mode: mode,
      effort: effort,
      efforts: efforts,
      running: running,
      busy: busy,
      hintText: thread == null
          ? 'Message Codex…'
          : 'Add direction to this task…',
      onSend: () => action(send),
      onStop: running
          ? () => action(() async {
              await call('bridge.turn.interrupt', {
                'threadId': thread!['id'],
                'turnId': turnId,
              });
            })
          : null,
      onModelChanged: (value) => setState(() {
        model = value;
        effort = null;
      }),
      onEffortChanged: (value) => setState(() => effort = value),
      onModeChanged: (value) => setState(() => mode = value ?? mode),
    );
    final children = <Widget>[
      for (final item in items)
        RepaintBoundary(
          key: ValueKey(item['id']),
          child: _TimelineItem(
            isUser: item['type'] == 'userMessage',
            label: item['type'] == 'userMessage' ? 'You · now' : 'Codex · now',
            child: MarkdownBody(
              selectable: true,
              data:
                  item['text']?.toString() ??
                  (item['content'] as List? ?? [])
                      .map((c) => c['text'])
                      .join('\n'),
            ),
          ),
        ),
      if (diff.isNotEmpty)
        _TimelineItem(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Task diff',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  diff,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      if (running)
        const _TimelineItem(
          active: true,
          child: Text(
            'Working on the task',
            style: TextStyle(fontSize: 13, color: Color(0xff4b9b67)),
          ),
        ),
      if (!running && thread != null)
        TextButton.icon(
          onPressed: () => action(() async {
            final result = await call('bridge.artifact.list', {
              'threadId': thread!['id'],
            });
            artifacts = result['payload']['artifacts'] as List;
            refresh();
          }),
          icon: const Icon(Icons.attach_file, size: 16),
          label: const Text('View artifacts'),
        ),
      for (final artifact in artifacts)
        ListTile(
          dense: true,
          leading: const Icon(Icons.download_outlined, size: 18),
          title: Text(
            artifact['name'] as String,
            style: const TextStyle(fontSize: 13),
          ),
          onTap: () =>
              action(() => download(Map<String, dynamic>.from(artifact))),
        ),
    ];
    final body = GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx.abs() < details.delta.dy.abs()) return;
        setState(() {
          drawerDragging = true;
          drawerPosition = (drawerPosition + details.delta.dx).clamp(
            0,
            drawerWidth,
          );
        });
      },
      onHorizontalDragEnd: (_) {
        setDrawer(drawerPosition > drawerWidth * .45);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: drawerWidth,
                child: Container(
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.paddingOf(context).top + 24,
                    16,
                    MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Chats',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.3,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            sectionLabel('Pinned', alias: '置顶'),
                            if (pinnedThreads.isEmpty)
                              const Text(
                                'No pinned chats',
                                style: TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              )
                            else
                              for (final chat in pinnedThreads)
                                threadTile(chat),
                            const SizedBox(height: 18),
                            sectionLabel('Projects', alias: '项目'),
                            if (projectChats.isEmpty)
                              const Text(
                                'No project chats',
                                style: TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              )
                            else
                              for (final projectId in [
                                for (final project in projects)
                                  if (projectChats.containsKey(
                                    project['projectId'],
                                  ))
                                    project['projectId'] as String,
                                for (final id in projectChats.keys)
                                  if (!projects.any(
                                    (project) => project['projectId'] == id,
                                  ))
                                    id,
                              ]) ...[
                                Builder(
                                  builder: (context) {
                                    final expanded =
                                        legacyExpandedProjectId == projectId;
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        key: PageStorageKey(
                                          'project-$projectId',
                                        ),
                                        onTap: () => setState(
                                          () => legacyExpandedProjectId =
                                              expanded ? null : projectId,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                expanded
                                                    ? Icons.keyboard_arrow_down
                                                    : Icons.chevron_right,
                                                size: 16,
                                                color: _muted,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  projectLabel(projectId)
                                                          .isEmpty
                                                      ? projectId
                                                      : projectLabel(projectId),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${projectChats[projectId]!.length}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: _muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (legacyExpandedProjectId == projectId)
                                  for (final chat in projectChats[projectId]!)
                                    threadTile(chat),
                              ],
                            const SizedBox(height: 18),
                            sectionLabel(
                              'Conversations',
                              alias: '对话',
                              aliases: const ['最近'],
                            ),
                            if (conversationThreads.isEmpty)
                              const Text(
                                'No conversations',
                                style: TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              )
                            else
                              for (final chat in conversationThreads)
                                threadTile(chat),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('new-chat'),
                            onPressed: busy || backend == null
                                ? null
                                : () {
                                    setDrawer(false);
                                    action(createThread);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Chat'),
                                Opacity(opacity: 0, child: Text('新建聊天')),
                              ],
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(108, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              backgroundColor: const Color(0xff0a84ff),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Settings'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.computer_outlined,
                                      ),
                                      title: const Text('Connected computer'),
                                      subtitle: Text(client.status),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        action(pair);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.tune_rounded),
                                      title: const Text('Preferences'),
                                      trailing: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(38, 38),
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xff151515),
                              shadowColor: const Color(0x1f191916),
                              elevation: 2,
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              side: const BorderSide(color: Color(0xffdeded9)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: drawerDragging
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: drawerPosition,
            right: -drawerPosition,
            top: 0,
            bottom: 0,
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: open
                      ? const BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(36),
                            bottomLeft: Radius.circular(36),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x3d1c1c19),
                              blurRadius: 11,
                              offset: Offset(-5, 0),
                            ),
                            BoxShadow(
                              color: Color(0x1c1c1c19),
                              blurRadius: 18,
                              offset: Offset(-11, 0),
                            ),
                          ],
                        )
                      : const BoxDecoration(),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(36),
                      bottomLeft: Radius.circular(36),
                    ),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: _surface),
                        ),
                        Positioned.fill(
                          child: SafeArea(
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    7,
                                  ),
                                  child: Row(
                                    children: [
                                      menuButton(),
                                      const SizedBox(width: 12),
                                      if (thread != null) ...[
                                        IconButton(
                                          tooltip: '刷新',
                                          onPressed: () => action(load),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: 28,
                                                height: 28,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: thread == null ? 22 : 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: client.status == '已连接'
                                              ? const Color(0xff6d9b7f)
                                              : const Color(0xffb0b0b0),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        client.status == '已连接'
                                            ? 'Connected'
                                            : client.status,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: _muted,
                                        ),
                                      ),
                                      if (thread?['title'] == '新聊天')
                                        const SizedBox.shrink(
                                          child: Opacity(
                                            opacity: 0,
                                            child: Text('新聊天'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (thread != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      64,
                                      0,
                                      16,
                                      6,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        statusLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: running
                                              ? const Color(0xff4b9b67)
                                              : const Color(0xff858585),
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: thread == null
                                      ? LayoutBuilder(
                                          builder: (context, constraints) =>
                                              SingleChildScrollView(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 17,
                                                    ),
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    minHeight:
                                                        constraints.maxHeight,
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Container(
                                                        width: 39,
                                                        height: 39,
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 20,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _ink,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                13,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.auto_awesome,
                                                          size: 19,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const Text(
                                                        'What are we building today?',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          letterSpacing: -.8,
                                                          height: 1.08,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Text(
                                                        client.status == '已连接'
                                                            ? 'Start a task with your connected workspace. Codex will keep the work moving while you stay in control.'
                                                            : 'Connect a computer to get started',
                                                        style: const TextStyle(
                                                          color: _muted,
                                                          fontSize: 12,
                                                          height: 1.5,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      for (
                                                        var index = 0;
                                                        index < 3;
                                                        index++
                                                      )
                                                        _SuggestionRow(
                                                          label: const [
                                                            'Review a diff',
                                                            'Plan a feature',
                                                            'Fix a bug',
                                                          ][index],
                                                          isFirst: index == 0,
                                                          onTap: () {
                                                            input.text = const [
                                                              'Review a diff',
                                                              'Plan a feature',
                                                              'Fix a bug',
                                                            ][index];
                                                            setDrawer(false);
                                                          },
                                                        ),
                                                      const SizedBox.shrink(
                                                        child: Opacity(
                                                          opacity: 0,
                                                          child: Text('打开聊天列表'),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                        )
                                      : ListView(
                                          key: PageStorageKey(thread!['id']),
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            12,
                                            20,
                                            20,
                                          ),
                                          children: [
                                            if (notice.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: Text(
                                                  notice,
                                                  maxLines: 3,
                                                  style: const TextStyle(
                                                    color: Color(0xffa05b42),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            if (unknownRequest != null)
                                              TextButton(
                                                onPressed: () =>
                                                    action(() async {
                                                      final result = await call(
                                                        'bridge.request.get',
                                                        {
                                                          'requestId':
                                                              unknownRequest,
                                                        },
                                                      );
                                                      setNotice(
                                                        jsonEncode(
                                                          result['payload'],
                                                        ),
                                                      );
                                                    }),
                                                child: const Text(
                                                  'Check the previous request result',
                                                ),
                                              ),
                                            for (final request
                                                in approvals.values)
                                              _ApprovalRow(
                                                request: request,
                                                onTap: () => action(
                                                  () => respond(request),
                                                ),
                                              ),
                                            ...children,
                                          ],
                                        ),
                                ),
                                composer,
                                SizedBox(
                                  height: busy ? 3 : 8,
                                  child: busy
                                      ? const LinearProgressIndicator(
                                          minHeight: 3,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (open)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(color: Color(0x1f000000)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (open)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: width - drawerWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setDrawer(false),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Material(color: _surface, child: body);
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    subscription?.cancel();
    client.removeListener(refresh);
    if (ownsClient) client.dispose();
    input.dispose();
    super.dispose();
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.label,
    required this.isFirst,
    required this.onTap,
  });

  final String label;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            top: isFirst ? const BorderSide(color: _line) : BorderSide.none,
            bottom: const BorderSide(color: _line),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xff6c6d67)),
              ),
            ),
            const Icon(
              Icons.north_east_rounded,
              size: 14,
              color: Color(0xffa7a8a1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: .02,
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.child,
    this.isUser = false,
    this.active = false,
    this.label,
  });
  final Widget child;
  final bool isUser;
  final bool active;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3, bottom: 18),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 18,
              child: Column(
                children: [
                  Container(
                    width: active ? 8 : 7,
                    height: active ? 8 : 7,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xff4d6f62)
                          : isUser
                          ? _ink
                          : const Color(0xffb4b7b2),
                      shape: BoxShape.circle,
                      border: isUser || active
                          ? null
                          : Border.all(color: const Color(0xffc3c5c0)),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0x66e7f0eb),
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Container(width: 1, color: const Color(0xffd9dad5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isUser
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (label != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _TimelineLabel(label!),
                            ),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 310),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xffe6e8e4),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(15),
                                topRight: Radius.circular(15),
                                bottomLeft: Radius.circular(15),
                                bottomRight: Radius.circular(5),
                              ),
                            ),
                            child: child,
                          ),
                        ],
                      ),
                    )
                  : DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 14, height: 1.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (label != null) _TimelineLabel(label!),
                          child,
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.request, required this.onTap});
  final Map<String, dynamic> request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xffe5e5e5)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.help_outline_rounded, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  request['method'] == 'item/tool/requestUserInput'
                      ? 'Input needed to continue'
                      : 'Approval needed to continue',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xff999999),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerSelect extends StatelessWidget {
  const _ComposerSelect({
    required this.value,
    required this.labels,
    required this.onChanged,
    this.leading,
    this.placeholder,
  });

  final String? value;
  final Map<String, String> labels;
  final IconData? leading;
  final String? placeholder;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 27),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _wash,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 12, color: const Color(0xff666761)),
            const SizedBox(width: 4),
          ],
          DropdownButton<String>(
            value: value,
            hint: placeholder == null
                ? null
                : Text(
                    placeholder!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff666761),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            isDense: true,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 13),
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xff666761),
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final entry in labels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.model,
    required this.models,
    required this.mode,
    required this.effort,
    required this.efforts,
    required this.running,
    required this.busy,
    required this.hintText,
    required this.onSend,
    required this.onStop,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onModeChanged,
  });
  final TextEditingController input;
  final String? model, effort;
  final List<String> models;
  final String mode;
  final List<String> efforts;
  final bool running, busy;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final ValueChanged<String?> onModelChanged, onEffortChanged, onModeChanged;

  @override
  Widget build(BuildContext context) {
    final availableModels = models.isEmpty
        ? <String>[model ?? 'GPT-5.6']
        : models;
    final selectedModel = availableModels.contains(model)
        ? model
        : availableModels.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: const Color(0xffd9dad4)),
          borderRadius: BorderRadius.circular(17),
        ),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Column(
          children: [
            TextField(
              controller: input,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            Row(
              children: [
                _ComposerSelect(
                  value: mode,
                  leading: Icons.route_outlined,
                  labels: const {'default': 'Default', 'plan': 'Plan'},
                  onChanged: onModeChanged,
                ),
                const SizedBox(width: 6),
                _ComposerSelect(
                  value: selectedModel,
                  labels: {for (final value in availableModels) value: value},
                  onChanged: onModelChanged,
                ),
                if (efforts.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  _ComposerSelect(
                    value: effort,
                    labels: {for (final value in efforts) value: value},
                    placeholder: 'Effort',
                    onChanged: onEffortChanged,
                  ),
                ],
                const Spacer(),
                if (running && onStop != null)
                  IconButton(
                    tooltip: 'Stop',
                    onPressed: busy ? null : onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 31,
                      height: 31,
                    ),
                  ),
                IconButton.filled(
                  tooltip: running ? 'Steer' : '发送',
                  onPressed: busy ? null : onSend,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
