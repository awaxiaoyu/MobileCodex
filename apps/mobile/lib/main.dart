import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'bridge_client.dart';

void main() => runApp(const MobileCodexApp());

class MobileCodexApp extends StatelessWidget {
  const MobileCodexApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mobile Codex',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
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

  Widget sectionHeading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );

  Widget threadTile(Map<String, dynamic> chat) {
    final id = chat['id'] as String;
    final pinned = pinnedThreadIds.contains(id);
    return ListTile(
      key: ValueKey('thread-$id'),
      dense: true,
      selected: id == thread?['id'],
      title: Text(
        chat['title']?.toString() ?? '聊天',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('thread-actions-$id'),
        tooltip: '会话操作',
        onSelected: (_) => togglePinned(chat),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: ValueKey('pin-thread-$id'),
            value: 'pin',
            child: Text(pinned ? '取消置顶' : '置顶'),
          ),
        ],
      ),
      onTap: () {
        Navigator.pop(context);
        action(() => selectThread(Map<String, dynamic>.from(chat)));
      },
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
    threads = chats['payload']['threads'] as List;
    final catalog = await call('bridge.model.list', {'limit': 100});
    models = (catalog['payload']['data'] as List)
        .where((m) => m['hidden'] != true)
        .toList();
    if (!models.any((m) => m['model'] == model)) {
      model =
          (models.where((m) => m['isDefault'] == true).firstOrNull ??
                  models.first)['model']
              as String;
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
    // A new Desktop thread has no rollout yet. Its create response is the
    // initial state; resume/read only becomes available after the first turn.
    newThreads.add(selected['id'] as String);
    threads = [selected, ...threads.where((t) => t['id'] != selected['id'])];
    await selectThread(selected);
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || thread == null) return;
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
      await client.pair(value, Platform.isIOS ? 'iPhone' : 'Android');
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
    final selectedModel = models.where((m) => m['model'] == model).firstOrNull;
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
    final pinnedChats = [
      for (final id in pinnedThreadIds)
        {...?pinnedThreadSummaries[id], ...?threadsById[id]},
    ];
    final projectIds = projects
        .whereType<Map>()
        .map((p) => p['projectId'])
        .whereType<String>()
        .toSet();
    final recentThreads = threadsById.values.where(
      (chat) =>
          !pinnedThreadIds.contains(chat['id']) &&
          (!projectIds.contains(chat['projectId']) || chat['projectId'] == null),
    );
    return Scaffold(
      key: scaffold,
      appBar: AppBar(
        title: const Text('Mobile Codex'),
        actions: [
          IconButton(
            tooltip: '连接电脑',
            onPressed: () => action(pair),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => action(load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(client.status),
                trailing: IconButton(
                  tooltip: '忘记电脑',
                  onPressed: client.forget,
                  icon: const Icon(Icons.link_off),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建聊天'),
                enabled: !busy && backend != null,
                onTap: busy || backend == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        action(createThread);
                      },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: const InputDecoration(labelText: '新聊天的项目'),
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(
                        value: p['projectId'] as String,
                        child: Text(p['label'] as String),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => projectId = value ?? projectId),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    sectionHeading('置顶'),
                    for (final chat in pinnedChats) threadTile(chat),
                    sectionHeading('项目'),
                    for (final project in projects)
                      ExpansionTile(
                        key: PageStorageKey('project-${project['projectId']}'),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(
                          project['label']?.toString() ?? '项目',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        children: [
                          for (final chat in threadsById.values.where(
                            (chat) =>
                                chat['projectId'] == project['projectId'] &&
                                !pinnedThreadIds.contains(chat['id']),
                          ))
                            threadTile(chat),
                          if (!threadsById.values.any(
                            (chat) =>
                                chat['projectId'] == project['projectId'] &&
                                !pinnedThreadIds.contains(chat['id']),
                          ))
                            const ListTile(
                              dense: true,
                              title: Text('暂无会话'),
                              enabled: false,
                            ),
                        ],
                      ),
                    sectionHeading('最近'),
                    for (final chat in recentThreads) threadTile(chat),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListTile(
              dense: true,
              title: Text(thread?['title']?.toString() ?? '选择聊天，继续电脑上的任务'),
              subtitle: Text(client.status),
              trailing: running
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            if (notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(notice, maxLines: 3),
              ),
            if (unknownRequest != null)
              TextButton(
                onPressed: () => action(() async {
                  final result = await call('bridge.request.get', {
                    'requestId': unknownRequest,
                  });
                  setNotice(jsonEncode(result['payload']));
                }),
                child: const Text('查询刚才操作的结果'),
              ),
            for (final request in approvals.values)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.question_answer),
                  title: const Text('需要你的回复'),
                  subtitle: Text(
                    request['method'] == 'item/tool/requestUserInput'
                        ? '回答任务中的问题'
                        : request['method'] ==
                              'item/permissions/requestApproval'
                        ? '确认任务需要的额外权限'
                        : '查看详情并决定是否继续',
                  ),
                  onTap: () => action(() => respond(request)),
                ),
              ),
            Expanded(
              key: const ValueKey('conversation'),
              child: thread == null
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: () => scaffold.currentState?.openDrawer(),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('打开聊天列表'),
                      ),
                    )
                  : ListView(
                      key: PageStorageKey(thread!['id']),
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final item in items)
                          RepaintBoundary(
                            key: ValueKey(item['id']),
                            child: Card(
                              color: item['type'] == 'userMessage'
                                  ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
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
                          ),
                        if (diff.isNotEmpty)
                          ExpansionTile(
                            title: const Text('任务 Diff'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  diff,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (!running)
                          TextButton(
                            onPressed: () => action(() async {
                              final result = await call(
                                'bridge.artifact.list',
                                {'threadId': thread!['id']},
                              );
                              artifacts =
                                  result['payload']['artifacts'] as List;
                              refresh();
                            }),
                            child: const Text('查看结果附件'),
                          ),
                        for (final artifact in artifacts)
                          ListTile(
                            leading: const Icon(Icons.download),
                            title: Text(artifact['name'] as String),
                            onTap: () => action(
                              () =>
                                  download(Map<String, dynamic>.from(artifact)),
                            ),
                          ),
                      ],
                    ),
            ),
            if (thread != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: model,
                      hint: const Text('Model'),
                      items: [
                        for (final m in models)
                          DropdownMenuItem(
                            value: m['model'] as String,
                            child: Text(
                              m['displayName']?.toString() ??
                                  m['model'].toString(),
                            ),
                          ),
                      ],
                      onChanged: running
                          ? null
                          : (value) => setState(() {
                              model = value;
                              effort = null;
                            }),
                    ),
                    DropdownButton<String>(
                      value: effort,
                      hint: const Text('Effort'),
                      items: [
                        for (final e in efforts)
                          DropdownMenuItem(value: e, child: Text(e)),
                      ],
                      onChanged: running
                          ? null
                          : (value) => setState(() => effort = value),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'default', label: Text('Default')),
                        ButtonSegment(value: 'plan', label: Text('Plan')),
                      ],
                      selected: {mode},
                      onSelectionChanged: running
                          ? null
                          : (value) => setState(() => mode = value.first),
                    ),
                  ],
                ),
              ),
            if (thread != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: running ? '追加方向…' : '让 Codex 做什么？',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: running ? 'Steer' : '发送',
                      onPressed: busy ? null : () => action(send),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    if (running)
                      IconButton(
                        tooltip: '停止',
                        onPressed: () => action(() async {
                          await call('bridge.turn.interrupt', {
                            'threadId': thread!['id'],
                            'turnId': turnId,
                          });
                        }),
                        icon: const Icon(Icons.stop_circle_outlined),
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: 4,
              child: busy ? const LinearProgressIndicator() : null,
            ),
          ],
        ),
      ),
    );
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
