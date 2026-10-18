import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_localizations.dart';
import 'bridge_client.dart';

const _ink = Color(0xff151515);
const _muted = Color(0xff8a8a86);
const _line = Color(0xffe8e7e2);
const _surface = Color(0xfff7f7f4);
const _panel = Color(0xffffffff);
const _wash = Color(0xffefefeb);

void main() => runApp(const MobileCodexApp());

class MobileCodexApp extends StatefulWidget {
  const MobileCodexApp({super.key});

  @override
  State<MobileCodexApp> createState() => _MobileCodexAppState();
}

class _MobileCodexAppState extends State<MobileCodexApp> {
  ThemeMode themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    unawaited(loadThemeMode());
  }

  Future<File> appearanceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/appearance.json');
  }

  Future<void> loadThemeMode() async {
    try {
      final file = await appearanceFile();
      if (!await file.exists()) return;
      final value = jsonDecode(await file.readAsString());
      final name = value is Map ? value['themeMode']?.toString() : null;
      final next = switch (name) {
        'system' => ThemeMode.system,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light,
      };
      if (mounted) setState(() => themeMode = next);
    } catch (_) {}
  }

  void updateThemeMode(ThemeMode value) {
    setState(() => themeMode = value);
    unawaited(() async {
      try {
        final file = await appearanceFile();
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode({'themeMode': value.name}));
      } catch (_) {}
    }());
  }

  ThemeData darkTheme() => ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff8ab4f8),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xff181818),
    canvasColor: const Color(0xff242424),
    cardColor: const Color(0xff242424),
    dividerColor: const Color(0xff3b3b3b),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xff181818),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Color(0xff2b2b2b),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xff444444)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xff444444)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xff9bbcff), width: 1.2),
      ),
      labelStyle: TextStyle(color: Color(0xffb7b7b7), fontSize: 12),
      hintStyle: TextStyle(color: Color(0xff9f9f9f), fontSize: 12),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 14),
      bodyMedium: TextStyle(fontSize: 13),
      bodySmall: TextStyle(fontSize: 11),
      labelLarge: TextStyle(fontSize: 12),
    ),
    useMaterial3: true,
  );

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        elevation: 8,
        menuPadding: EdgeInsets.symmetric(vertical: 5),
        textStyle: TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _ink, width: 1.2),
        ),
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
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(11)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(11)),
          ),
          side: const BorderSide(color: _line),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titleTextStyle: TextStyle(
          color: _ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      fontFamily: 'SF Pro Text',
      useMaterial3: true,
    ),
    darkTheme: darkTheme(),
    themeMode: themeMode,
    home: TaskPage(themeMode: themeMode, onThemeModeChanged: updateThemeMode),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    this.client,
    this.themeMode = ThemeMode.light,
    this.onThemeModeChanged,
  });
  final BridgeClient? client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
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
  late final Future<void> preferencesLoad;
  Map<String, dynamic>? backend, thread;
  bool desktopReady = false;
  final approvals = <String, Map<String, dynamic>>{};
  final buffered = <Map<String, dynamic>>[];
  final newThreads = <String>{};
  double drawerPosition = 0;
  bool drawerDragging = false;
  String? legacyExpandedProjectId;
  String? model, effort, turnId, streamId, unknownRequest;
  String mode = 'default', diff = '', notice = '';
  final expandedCompletedTurns = <String>{};
  bool showReasoningSummaries = false;
  bool collapseCompletedTurns = true;
  bool voiceInputEnabled = false;
  bool autoSendVoice = false;
  String voiceLanguage = 'auto';
  String responseStyle = 'none';
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
    preferencesLoad = loadPreferences();
    unawaited(pinnedLoad);
    unawaited(preferencesLoad);
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

  Future<File> preferencesFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/preferences.json');
  }

  Future<void> loadPreferences() async {
    try {
      final file = await preferencesFile();
      if (!await file.exists()) return;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return;
      if (!mounted) return;
      setState(() {
        showReasoningSummaries = value['showReasoningSummaries'] == true;
        collapseCompletedTurns = value['collapseCompletedTurns'] != false;
        voiceInputEnabled = value['voiceInputEnabled'] == true;
        autoSendVoice = value['autoSendVoice'] == true;
        final language = value['voiceLanguage']?.toString();
        if (language == 'auto' || language == 'zh' || language == 'en') {
          voiceLanguage = language!;
        }
        final style = value['responseStyle']?.toString();
        if (style == 'none' || style == 'friendly' || style == 'pragmatic') {
          responseStyle = style!;
        }
      });
    } catch (_) {
      // Preferences are optional; app startup must work without local storage.
    }
  }

  Future<void> persistPreferences() async {
    try {
      await preferencesLoad;
      final file = await preferencesFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'showReasoningSummaries': showReasoningSummaries,
          'collapseCompletedTurns': collapseCompletedTurns,
          'voiceInputEnabled': voiceInputEnabled,
          'autoSendVoice': autoSendVoice,
          'voiceLanguage': voiceLanguage,
          'responseStyle': responseStyle,
        }),
      );
    } catch (_) {}
  }

  Future<void> togglePinned(Map<String, dynamic> chat) async {
    final strings = AppLocalizations.of(context);
    await pinnedLoad;
    final id = chat['id'] as String;
    setState(() {
      if (pinnedThreadIds.remove(id)) {
        pinnedThreadSummaries.remove(id);
      } else {
        pinnedThreadIds.add(id);
        pinnedThreadSummaries[id] = {
          'id': id,
          'title': chat['title']?.toString() ?? strings.chat,
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

  String projectBranch(String? projectId) {
    if (projectId == null) return '';
    final project = projects
        .where((p) => p['projectId'] == projectId)
        .firstOrNull;
    return project?['branch']?.toString() ?? '';
  }

  String chatTitle(Map<String, dynamic> chat) {
    final strings = AppLocalizations.of(context);
    final title = chat['title']?.toString().trim();
    final name = title == null || title.isEmpty
        ? strings.untitledChat
        : isNewChatTitle(title)
        ? strings.newChat
        : title;
    final project = projectLabel(chat['projectId'] as String?);
    return project.isEmpty ? name : '$project/$name';
  }

  String chatName(Map<String, dynamic> chat, AppLocalizations strings) {
    final title = chat['title']?.toString().trim();
    if (title == null || title.isEmpty) return strings.untitledChat;
    return isNewChatTitle(title) ? strings.newChat : title;
  }

  bool isNewChatTitle(String title) =>
      const {'新聊天', 'New chat', 'Untitled chat', 'Untitled'}.contains(title);

  String chatMeta(Map<String, dynamic> chat, AppLocalizations strings) {
    return chat['mode']?.toString().toLowerCase() == 'plan'
        ? strings.planMode
        : strings.defaultMode;
  }

  String localizedConnectionStatus(AppLocalizations strings) {
    if (client.status == '已连接' && !desktopReady) {
      return strings.desktopOffline;
    }
    final status = client.status;
    if (status == '已连接') return strings.connected;
    if (status == '连接中') return strings.connecting;
    if (status == '连接中断') return strings.disconnected;
    if (status == '未连接') return strings.notConnected;
    if (status == '设备已撤销，请重新配对') return strings.deviceRevoked;
    if (status.startsWith('连接失败')) return strings.connectionFailed;
    return status;
  }

  bool hasThreadContent(Map<String, dynamic> chat) {
    if (newThreads.contains(chat['id'])) return false;
    final turns = chat['turns'];
    if (turns is List) {
      final hasVisibleTurn = turns.any((turn) {
        if (turn is! Map) return false;
        final items = turn['items'];
        if (items is! List) return false;
        return items.any(
          (item) =>
              item is Map &&
              isVisibleTimelineItem(Map<String, dynamic>.from(item)),
        );
      });
      if (hasVisibleTurn) return true;
    }
    for (final key in const [
      'preview',
      'summary',
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
    final title = chat['title']?.toString().trim();
    final hasThreadMetadata =
        chat['status'] != null ||
        chat['createdAt'] != null ||
        chat['updatedAt'] != null ||
        chat['projectId'] != null;
    return title != null &&
        title.isNotEmpty &&
        !isNewChatTitle(title) &&
        (hasThreadMetadata ||
            pinnedThreadIds.contains(chat['id']) ||
            isRemotePinned(chat));
  }

  bool isRemotePinned(Map<String, dynamic> chat) =>
      chat['pinned'] == true ||
      chat['isPinned'] == true ||
      chat['pinnedSummary'] == true;

  String? itemText(Map<String, dynamic> item) {
    final direct = item['text']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final content = item['content'];
    if (content is List) {
      final text = content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.trim().isNotEmpty)
          .join('\n')
          .trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  bool isVisibleTimelineItem(Map<String, dynamic> item) {
    const visibleTypes = {'userMessage', 'agentMessage', 'plan', 'reasoning'};
    return visibleTypes.contains(item['type']) && itemText(item) != null;
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
    tooltip: AppLocalizations.of(context).openMenu,
    onPressed: () => setDrawer(drawerPosition == 0),
    icon: const Icon(Icons.menu_rounded, size: 19),
    style: IconButton.styleFrom(
      fixedSize: const Size(34, 34),
      backgroundColor: Theme.of(context).cardColor,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      shadowColor: const Color(0x2e191916),
      elevation: 3,
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    ),
  );

  Widget sectionLabel(String title) => Padding(
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
      ],
    ),
  );

  Widget threadTile(Map<String, dynamic> chat, AppLocalizations strings) {
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
                          chatName(chat, strings),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          chatMeta(chat, strings),
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
              Positioned(
                top: 0,
                right: 0,
                child: Opacity(
                  opacity: 0,
                  child: PopupMenuButton<String>(
                    key: ValueKey('thread-actions-$id'),
                    tooltip: strings.chatActions,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (_) => togglePinned(chat),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: ValueKey('pin-thread-$id'),
                        value: 'pin',
                        child: Text(pinned ? strings.unpin : strings.pin),
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
    final strings = AppLocalizations.of(context);
    final result = await client.rpc('bridge.backends.list', {});
    final backends = result['payload']['backends'] as List;
    final shared = backends
        .where(
          (b) => b['kind'] == 'desktop-shared' && b['status'] == 'connected',
        )
        .firstOrNull;
    desktopReady = shared != null;
    if (shared == null) {
      setNotice(strings.computerDisconnected);
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
    final projectData = catalogProjects['payload']['projects'];
    projects = (projectData is List ? projectData : const [])
        .whereType<Map>()
        .map(
          (p) => {
            'projectId': p['projectId'] ?? p['id'],
            'label': p['label'] ?? p['name'] ?? p['projectId'] ?? p['id'],
            if (p['branch'] != null || p['branchName'] != null)
              'branch': p['branch'] ?? p['branchName'],
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
    for (final value in threads) {
      final id = value is Map<String, dynamic> ? value['id'] : null;
      if (id is String &&
          value is Map<String, dynamic> &&
          isRemotePinned(value)) {
        pinnedThreadIds.add(id);
        pinnedThreadSummaries[id] = value;
      }
    }
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
    if (notice == strings.computerDisconnected) notice = '';
    refresh();
  }

  void onEvent(Map<String, dynamic> event) {
    if (event['method'] == 'event.connection.ready') {
      unawaited(load().catchError((Object e) => setNotice(e.toString())));
      return;
    }
    if (event['method'] == 'event.backend.status') {
      desktopReady = event['payload']?['status'] == 'connected';
      if (desktopReady) {
        unawaited(load().catchError((Object e) => setNotice(e.toString())));
      } else {
        setNotice(AppLocalizations.of(context).computerDisconnected);
      }
      refresh();
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
      final turns = thread?['turns'];
      if (turns is List && p['status'] is String) {
        final updatedTurn = turns
            .whereType<Map>()
            .where((value) => value['id'] == turnId)
            .firstOrNull;
        if (updatedTurn != null) updatedTurn['status'] = p['status'];
      }
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
        item = {
          'id': p['itemId'],
          'type': p['type'] as String? ?? 'agentMessage',
          'text': '',
        };
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
    expandedCompletedTurns.clear();
    streamId = null;
    seq = 0;
    await snapshot();
    refresh();
  }

  Future<void> createThread() async {
    final strings = AppLocalizations.of(context);
    final created = await call('bridge.thread.create', {
      'projectId': projectId,
    });
    final selected = Map<String, dynamic>.from(created['payload']['thread']);
    selected['projectId'] = projectId;
    if ((selected['title'] as String? ?? '').isEmpty) {
      selected['title'] = strings.newChat;
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
    final strings = AppLocalizations.of(context);
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
        if (!running && responseStyle != 'none') 'personality': responseStyle,
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
    if (currentTitle == null ||
        currentTitle.isEmpty ||
        isNewChatTitle(currentTitle)) {
      thread!['title'] = submittedText.length > 80
          ? '${submittedText.substring(0, 80)}…'
          : submittedText;
    }
    rememberThread(thread!);
    running = true;
    input.clear();
    setNotice(strings.taskSubmitted);
  }

  Future<void> respond(Map<String, dynamic> request) async {
    final strings = AppLocalizations.of(context);
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
                  decoration: InputDecoration(labelText: strings.ownAnswer),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(strings.later),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, text.text),
                child: Text(strings.submit),
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
          title: Text(strings.approvalRequired),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(p),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'decline'),
              child: Text(strings.decline),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'accept'),
              child: Text(strings.allowThisTime),
            ),
          ],
        ),
      );
      if (decision != null) result = {'decision': decision};
    } else if (method == 'item/permissions/requestApproval') {
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.additionalPermissions),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(p),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(strings.decline),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strings.allowCurrentTask),
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
        setNotice(strings.unsupportedApproval);
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
            title: Text(p['message']?.toString() ?? strings.formRequired),
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
                        borderRadius: BorderRadius.circular(12),
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
                child: Text(strings.decline),
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
                        () => formError = strings.t(
                          'fillAnswer',
                          args: {
                            'field': (entry.value['title'] ?? entry.key)
                                .toString(),
                          },
                        ),
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
                        () => formError = strings.t(
                          'invalidNumber',
                          args: {
                            'field': (entry.value['title'] ?? entry.key)
                                .toString(),
                          },
                        ),
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
                child: Text(strings.submit),
              ),
            ],
          ),
        ),
      );
      for (final control in controls.values) {
        control.dispose();
      }
    } else {
      setNotice(strings.unsupportedInteraction);
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
    final strings = AppLocalizations.of(context);
    final edit = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(strings.connectComputer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: edit,
                minLines: 4,
                maxLines: 7,
                decoration: InputDecoration(labelText: strings.pairingInfo),
              ),
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('scan-pairing-code'),
                  onPressed: () async {
                    final code = await scanPairingCode(strings);
                    if (code != null) update(() => edit.text = code);
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                  label: Text(strings.scanPairingCode),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, edit.text),
              child: Text(strings.pair),
            ),
          ],
        ),
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

  Future<String?> scanPairingCode(AppLocalizations strings) {
    var didScan = false;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.scanPairingTitle),
        content: SizedBox(
          width: 300,
          height: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (didScan) return;
                    final value = capture.barcodes
                        .map((barcode) => barcode.rawValue)
                        .whereType<String>()
                        .firstOrNull;
                    if (value == null || value.trim().isEmpty) return;
                    didScan = true;
                    Navigator.pop(ctx, value.trim());
                  },
                  errorBuilder: (context, error) => ColoredBox(
                    color: _ink,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          strings.cameraUnavailable,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 218,
                      height: 218,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Text(
                      strings.scanPairingHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
        ],
      ),
    );
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

  void openSettings() {
    setDrawer(false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          statusLabel: localizedConnectionStatus(AppLocalizations.of(context)),
          desktopReady: desktopReady,
          models: models,
          selectedModel: model,
          selectedEffort: effort,
          mode: mode,
          projects: projects,
          selectedProjectId: projectId,
          themeMode: widget.themeMode,
          voiceInputEnabled: voiceInputEnabled,
          autoSendVoice: autoSendVoice,
          voiceLanguage: voiceLanguage,
          responseStyle: responseStyle,
          showReasoningSummaries: showReasoningSummaries,
          collapseCompletedTurns: collapseCompletedTurns,
          onPair: () => action(pair),
          onThemeModeChanged: widget.onThemeModeChanged,
          onModelChanged: (value) => setState(() {
            model = value;
            effort = null;
          }),
          onEffortChanged: (value) => setState(() => effort = value),
          onModeChanged: (value) => setState(() => mode = value),
          onProjectChanged: (value) => setState(() => projectId = value),
          onVoiceInputChanged: (value) {
            setState(() => voiceInputEnabled = value);
            unawaited(persistPreferences());
          },
          onAutoSendVoiceChanged: (value) {
            setState(() => autoSendVoice = value);
            unawaited(persistPreferences());
          },
          onVoiceLanguageChanged: (value) {
            setState(() => voiceLanguage = value);
            unawaited(persistPreferences());
          },
          onResponseStyleChanged: (value) {
            setState(() => responseStyle = value);
            unawaited(persistPreferences());
          },
          onShowReasoningChanged: (value) {
            setState(() => showReasoningSummaries = value);
            unawaited(persistPreferences());
          },
          onCollapseCompletedChanged: (value) {
            setState(() => collapseCompletedTurns = value);
            unawaited(persistPreferences());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final selectedModel = models
        .whereType<Map>()
        .where((m) => m['model'] == model || m['id'] == model)
        .firstOrNull;
    final efforts = (selectedModel?['supportedReasoningEfforts'] as List? ?? [])
        .map((e) => e['reasoningEffort'] as String)
        .toList();
    final turns = thread?['turns'] as List? ?? [];
    final threadsById = {
      for (final value in threads)
        if (value is Map && value['id'] is String)
          value['id'] as String: Map<String, dynamic>.from(value),
    };
    final visibleThreads = threadsById.values.where(hasThreadContent).toList();
    final pinnedThreads = visibleThreads
        .where(
          (chat) =>
              pinnedThreadIds.contains(chat['id']) || isRemotePinned(chat),
        )
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
        ? strings.running
        : localizedConnectionStatus(strings);
    final composerProjectId = thread?['projectId'] as String? ?? projectId;
    final composer = _Composer(
      input: input,
      strings: strings,
      projectLabel: projectLabel(composerProjectId),
      branchLabel: projectBranch(composerProjectId),
      locationLabel: client.status == '已连接' && desktopReady
          ? strings.local
          : null,
      model: model,
      models: modelOptions,
      mode: mode,
      effort: effort,
      efforts: efforts,
      running: running,
      busy: busy,
      hintText: thread == null ? strings.messageCodex : strings.addDirection,
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
    final timeline = <Widget>[];
    for (var turnIndex = 0; turnIndex < turns.length; turnIndex++) {
      final rawTurn = turns[turnIndex];
      if (rawTurn is! Map) continue;
      final currentTurn = Map<String, dynamic>.from(rawTurn);
      final turnItems = (currentTurn['items'] as List? ?? [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where(
            (item) =>
                isVisibleTimelineItem(item) &&
                (showReasoningSummaries ||
                    (item['type'] != 'plan' && item['type'] != 'reasoning')),
          )
          .toList();
      if (turnItems.isEmpty) continue;

      final turnKey = currentTurn['id']?.toString() ?? 'turn-$turnIndex';
      final completed = currentTurn['status'] == 'completed';
      final collapsed =
          completed &&
          collapseCompletedTurns &&
          !expandedCompletedTurns.contains(turnKey);
      final finalAnswer = turnItems
          .where((item) => item['type'] == 'agentMessage')
          .lastOrNull;
      final visibleItems = collapsed && finalAnswer != null
          ? [finalAnswer]
          : collapsed
          ? [turnItems.last]
          : turnItems;

      for (final item in visibleItems) {
        final isFinalAnswer =
            collapsed && finalAnswer != null && item['id'] == finalAnswer['id'];
        timeline.add(
          RepaintBoundary(
            key: ValueKey(item['id'] ?? '$turnKey-${timeline.length}'),
            child: _TimelineItem(
              isUser: item['type'] == 'userMessage',
              label: isFinalAnswer
                  ? strings.finalSummary
                  : item['type'] == 'userMessage'
                  ? strings.you
                  : strings.assistant,
              child: MarkdownBody(selectable: true, data: itemText(item)!),
            ),
          ),
        );
      }

      if (collapsed && turnItems.length > visibleItems.length) {
        timeline.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('expand-turn-$turnKey'),
              onPressed: () =>
                  setState(() => expandedCompletedTurns.add(turnKey)),
              icon: const Icon(Icons.expand_more_rounded, size: 17),
              label: Text(strings.showFullConversation),
            ),
          ),
        );
      } else if (completed &&
          collapseCompletedTurns &&
          expandedCompletedTurns.contains(turnKey)) {
        timeline.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('collapse-turn-$turnKey'),
              onPressed: () =>
                  setState(() => expandedCompletedTurns.remove(turnKey)),
              icon: const Icon(Icons.expand_less_rounded, size: 17),
              label: Text(strings.hideFullConversation),
            ),
          ),
        );
      }
    }

    final children = <Widget>[
      ...timeline,
      if (diff.isNotEmpty)
        _TimelineItem(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              strings.taskDiff,
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
        _TimelineItem(
          active: true,
          child: Text(
            strings.working,
            style: const TextStyle(fontSize: 13, color: Color(0xff4b9b67)),
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
          label: Text(strings.viewArtifacts),
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
                  color: Theme.of(context).cardColor,
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
                          Text(
                            strings.chats,
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
                            sectionLabel(strings.pinned),
                            if (pinnedThreads.isEmpty)
                              Text(
                                strings.noPinnedChats,
                                style: TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              )
                            else
                              for (final chat in pinnedThreads)
                                threadTile(chat, strings),
                            const SizedBox(height: 18),
                            sectionLabel(strings.projects),
                            if (projectChats.isEmpty)
                              Text(
                                strings.noProjectChats,
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
                                    threadTile(chat, strings),
                              ],
                            const SizedBox(height: 18),
                            sectionLabel(strings.conversations),
                            if (conversationThreads.isEmpty)
                              Text(
                                strings.noConversations,
                                style: TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              )
                            else
                              for (final chat in conversationThreads)
                                threadTile(chat, strings),
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
                            label: Text(strings.chat),
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
                            tooltip: strings.settings,
                            onPressed: openSettings,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(38, 38),
                              backgroundColor: Theme.of(context).cardColor,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
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
                        Positioned.fill(
                          child: ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
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
                                          tooltip: strings.refresh,
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
                                          color:
                                              client.status == '已连接' &&
                                                  desktopReady
                                              ? const Color(0xff6d9b7f)
                                              : const Color(0xffb0b0b0),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        client.status == '已连接' && desktopReady
                                            ? strings.connected
                                            : localizedConnectionStatus(
                                                strings,
                                              ),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: _muted,
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
                                                        clipBehavior:
                                                            Clip.antiAlias,
                                                        child: Image.asset(
                                                          'assets/brand/mobile_codex_logo.png',
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                      Text(
                                                        strings.welcomeTitle,
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
                                                            ? strings.t(
                                                                'welcomeConnected',
                                                              )
                                                            : strings.t(
                                                                'welcomeDisconnected',
                                                              ),
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
                                                          label: [
                                                            strings.reviewDiff,
                                                            strings.planFeature,
                                                            strings.fixBug,
                                                          ][index],
                                                          isFirst: index == 0,
                                                          onTap: () {
                                                            input.text = [
                                                              strings
                                                                  .reviewDiff,
                                                              strings
                                                                  .planFeature,
                                                              strings.fixBug,
                                                            ][index];
                                                            setDrawer(false);
                                                          },
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
                                                child: Text(
                                                  strings.checkRequestResult,
                                                ),
                                              ),
                                            for (final request
                                                in approvals.values)
                                              _ApprovalRow(
                                                strings: strings,
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
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: body,
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.statusLabel,
    required this.desktopReady,
    required this.models,
    required this.selectedModel,
    required this.selectedEffort,
    required this.mode,
    required this.projects,
    required this.selectedProjectId,
    required this.themeMode,
    required this.voiceInputEnabled,
    required this.autoSendVoice,
    required this.voiceLanguage,
    required this.responseStyle,
    required this.showReasoningSummaries,
    required this.collapseCompletedTurns,
    required this.onPair,
    required this.onThemeModeChanged,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onModeChanged,
    required this.onProjectChanged,
    required this.onVoiceInputChanged,
    required this.onAutoSendVoiceChanged,
    required this.onVoiceLanguageChanged,
    required this.onResponseStyleChanged,
    required this.onShowReasoningChanged,
    required this.onCollapseCompletedChanged,
  });

  final String statusLabel;
  final bool desktopReady;
  final List<dynamic> models, projects;
  final String? selectedModel, selectedEffort, selectedProjectId;
  final String mode, voiceLanguage;
  final String responseStyle;
  final ThemeMode themeMode;
  final bool voiceInputEnabled, autoSendVoice;
  final bool showReasoningSummaries, collapseCompletedTurns;
  final VoidCallback onPair;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<String?> onModelChanged, onEffortChanged;
  final ValueChanged<String> onModeChanged, onProjectChanged;
  final ValueChanged<bool> onVoiceInputChanged, onAutoSendVoiceChanged;
  final ValueChanged<String> onVoiceLanguageChanged;
  final ValueChanged<String> onResponseStyleChanged;
  final ValueChanged<bool> onShowReasoningChanged, onCollapseCompletedChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final personal = <_SettingsEntry>[
      _SettingsEntry('general', strings.general, Icons.settings_outlined),
      _SettingsEntry('appearance', strings.appearance, Icons.wb_sunny_outlined),
      _SettingsEntry('voice', strings.voice, Icons.mic_none_rounded),
      _SettingsEntry('storage', strings.storage, Icons.folder_outlined),
    ];
    final computer = <_SettingsEntry>[
      _SettingsEntry(
        'configuration',
        strings.configuration,
        Icons.tune_rounded,
      ),
      _SettingsEntry(
        'personalization',
        strings.personalization,
        Icons.auto_awesome_outlined,
      ),
    ];
    final coding = <_SettingsEntry>[
      _SettingsEntry('git', strings.git, Icons.account_tree_outlined),
      _SettingsEntry('worktrees', strings.worktrees, Icons.call_split_rounded),
    ];

    bool matches(_SettingsEntry entry) =>
        query.trim().isEmpty ||
        entry.title.toLowerCase().contains(query.trim().toLowerCase());

    Widget group(String title, List<_SettingsEntry> entries) {
      final visible = entries.where(matches).toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
            child: Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .3,
              ),
            ),
          ),
          for (final entry in visible) _settingsRow(entry),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settings),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Text(
            strings.settingsDescription,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('settings-search'),
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              hintText: strings.searchSettings,
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: strings.cancel,
                      onPressed: () => setState(() => query = ''),
                      icon: const Icon(Icons.clear_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _computerConnectionCard(strings),
          group(strings.personal, personal),
          group(strings.computer, computer),
          group(strings.coding, coding),
        ],
      ),
    );
  }

  Widget _computerConnectionCard(AppLocalizations strings) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('settings-computer-card'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: widget.desktopReady
              ? const Color(0xffdff5e5)
              : theme.colorScheme.surface,
          foregroundColor: widget.desktopReady
              ? const Color(0xff287343)
              : theme.colorScheme.onSurfaceVariant,
          child: Icon(
            widget.desktopReady
                ? Icons.computer_rounded
                : Icons.computer_outlined,
            size: 20,
          ),
        ),
        title: Text(
          strings.connectedComputer,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${strings.bridgeStatus}: ${widget.statusLabel}'),
        trailing: TextButton(
          onPressed: widget.onPair,
          child: Text(
            widget.desktopReady ? strings.connected : strings.pairComputer,
          ),
        ),
        onTap: widget.onPair,
      ),
    );
  }

  Widget _settingsRow(_SettingsEntry entry) {
    final strings = AppLocalizations.of(context);
    final isMobile = const {
      'appearance',
      'voice',
      'storage',
    }.contains(entry.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        key: ValueKey('settings-${entry.id}'),
        minVerticalPadding: 9,
        leading: Icon(entry.icon, size: 21),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isMobile
              ? strings.mobileSettingsDescription
              : strings.computerSettingsDescription,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SettingsDetailPage(
              section: entry.id,
              statusLabel: widget.statusLabel,
              desktopReady: widget.desktopReady,
              models: widget.models,
              selectedModel: widget.selectedModel,
              selectedEffort: widget.selectedEffort,
              mode: widget.mode,
              projects: widget.projects,
              selectedProjectId: widget.selectedProjectId,
              themeMode: widget.themeMode,
              voiceInputEnabled: widget.voiceInputEnabled,
              autoSendVoice: widget.autoSendVoice,
              voiceLanguage: widget.voiceLanguage,
              responseStyle: widget.responseStyle,
              showReasoningSummaries: widget.showReasoningSummaries,
              collapseCompletedTurns: widget.collapseCompletedTurns,
              onPair: widget.onPair,
              onThemeModeChanged: widget.onThemeModeChanged,
              onModelChanged: widget.onModelChanged,
              onEffortChanged: widget.onEffortChanged,
              onModeChanged: widget.onModeChanged,
              onProjectChanged: widget.onProjectChanged,
              onVoiceInputChanged: widget.onVoiceInputChanged,
              onAutoSendVoiceChanged: widget.onAutoSendVoiceChanged,
              onVoiceLanguageChanged: widget.onVoiceLanguageChanged,
              onResponseStyleChanged: widget.onResponseStyleChanged,
              onShowReasoningChanged: widget.onShowReasoningChanged,
              onCollapseCompletedChanged: widget.onCollapseCompletedChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsEntry {
  const _SettingsEntry(this.id, this.title, this.icon);
  final String id, title;
  final IconData icon;
}

class _SettingsDetailPage extends StatefulWidget {
  const _SettingsDetailPage({
    required this.section,
    required this.statusLabel,
    required this.desktopReady,
    required this.models,
    required this.selectedModel,
    required this.selectedEffort,
    required this.mode,
    required this.projects,
    required this.selectedProjectId,
    required this.themeMode,
    required this.voiceInputEnabled,
    required this.autoSendVoice,
    required this.voiceLanguage,
    required this.responseStyle,
    required this.showReasoningSummaries,
    required this.collapseCompletedTurns,
    required this.onPair,
    required this.onThemeModeChanged,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onModeChanged,
    required this.onProjectChanged,
    required this.onVoiceInputChanged,
    required this.onAutoSendVoiceChanged,
    required this.onVoiceLanguageChanged,
    required this.onResponseStyleChanged,
    required this.onShowReasoningChanged,
    required this.onCollapseCompletedChanged,
  });

  final String section, statusLabel, mode, voiceLanguage;
  final String responseStyle;
  final bool desktopReady, voiceInputEnabled, autoSendVoice;
  final bool showReasoningSummaries, collapseCompletedTurns;
  final List<dynamic> models, projects;
  final String? selectedModel, selectedEffort, selectedProjectId;
  final ThemeMode themeMode;
  final VoidCallback onPair;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<String?> onModelChanged, onEffortChanged;
  final ValueChanged<String> onModeChanged, onProjectChanged;
  final ValueChanged<bool> onVoiceInputChanged, onAutoSendVoiceChanged;
  final ValueChanged<String> onVoiceLanguageChanged;
  final ValueChanged<String> onResponseStyleChanged;
  final ValueChanged<bool> onShowReasoningChanged, onCollapseCompletedChanged;

  @override
  State<_SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<_SettingsDetailPage> {
  late ThemeMode themeMode = widget.themeMode;
  late bool voiceInputEnabled = widget.voiceInputEnabled;
  late bool autoSendVoice = widget.autoSendVoice;
  late String voiceLanguage = widget.voiceLanguage;
  late bool showReasoningSummaries = widget.showReasoningSummaries;
  late bool collapseCompletedTurns = widget.collapseCompletedTurns;
  Future<_StorageUsage>? storageUsage;

  @override
  void initState() {
    super.initState();
    if (widget.section == 'storage') storageUsage = readStorageUsage();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final title = switch (widget.section) {
      'general' => strings.general,
      'appearance' => strings.appearance,
      'voice' => strings.voice,
      'storage' => strings.storage,
      'configuration' => strings.configuration,
      'personalization' => strings.personalization,
      'git' => strings.git,
      _ => strings.worktrees,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title), leading: const BackButton()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (widget.section == 'general') _general(strings),
          if (widget.section == 'appearance') _appearance(strings),
          if (widget.section == 'voice') _voice(strings),
          if (widget.section == 'storage') _storage(strings),
          if (widget.section == 'configuration') _configuration(strings),
          if (widget.section == 'personalization') _personalization(strings),
          if (widget.section == 'git') _git(strings),
          if (widget.section == 'worktrees') _worktrees(strings),
        ],
      ),
    );
  }

  Widget _heading(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          description,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  Widget _panel({required List<Widget> children}) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: .38),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: children),
    ),
  );

  Widget _general(AppLocalizations strings) {
    final modelOptions = widget.models
        .whereType<Map>()
        .map((value) => (value['model'] ?? value['id'])?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(strings.general, strings.computerSettingsDescription),
        _panel(
          children: [
            ListTile(
              leading: const Icon(Icons.computer_outlined),
              title: Text(strings.connectedComputer),
              subtitle: Text('${strings.bridgeStatus}: ${widget.statusLabel}'),
              trailing: OutlinedButton(
                onPressed: widget.onPair,
                child: Text(
                  widget.desktopReady ? strings.settings : strings.pairComputer,
                ),
              ),
              onTap: widget.onPair,
            ),
            const Divider(height: 12),
            if (modelOptions.isEmpty)
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(strings.defaultModel),
                subtitle: Text(strings.noContent),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: modelOptions.contains(widget.selectedModel)
                    ? widget.selectedModel
                    : modelOptions.first,
                decoration: InputDecoration(labelText: strings.defaultModel),
                items: [
                  for (final value in modelOptions)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) {
                  widget.onModelChanged(value);
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        _info(strings.desktopManagedHint),
      ],
    );
  }

  Widget _appearance(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.appearance, strings.mobileSettingsDescription),
      _panel(
        children: [
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) {
              if (value == null) return;
              setState(() => themeMode = value);
              widget.onThemeModeChanged?.call(value);
            },
            child: Column(
              children: [
                for (final entry in <(ThemeMode, String)>[
                  (ThemeMode.system, strings.systemTheme),
                  (ThemeMode.light, strings.lightTheme),
                  (ThemeMode.dark, strings.darkTheme),
                ])
                  RadioListTile<ThemeMode>(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(entry.$2),
                    value: entry.$1,
                  ),
              ],
            ),
          ),
          const Divider(height: 12),
          SwitchListTile.adaptive(
            title: Text(strings.showReasoningSummaries),
            subtitle: Text(strings.showReasoningSummariesHint),
            value: showReasoningSummaries,
            onChanged: (value) {
              setState(() => showReasoningSummaries = value);
              widget.onShowReasoningChanged(value);
            },
          ),
          SwitchListTile.adaptive(
            title: Text(strings.collapseCompletedTurns),
            subtitle: Text(strings.collapseCompletedTurnsHint),
            value: collapseCompletedTurns,
            onChanged: (value) {
              setState(() => collapseCompletedTurns = value);
              widget.onCollapseCompletedChanged(value);
            },
          ),
        ],
      ),
      const SizedBox(height: 8),
      _info(strings.themeHint),
    ],
  );

  Widget _voice(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.voice, strings.mobileSettingsDescription),
      _panel(
        children: [
          SwitchListTile.adaptive(
            title: Text(strings.voiceInput),
            subtitle: Text(strings.voiceInputHint),
            value: voiceInputEnabled,
            onChanged: (value) {
              setState(() => voiceInputEnabled = value);
              widget.onVoiceInputChanged(value);
            },
          ),
          SwitchListTile.adaptive(
            title: Text(strings.autoSendVoice),
            subtitle: Text(strings.autoSendVoiceHint),
            value: autoSendVoice,
            onChanged: voiceInputEnabled
                ? (value) {
                    setState(() => autoSendVoice = value);
                    widget.onAutoSendVoiceChanged(value);
                  }
                : null,
          ),
          ListTile(
            title: Text(strings.voiceLanguage),
            trailing: DropdownButton<String>(
              value: voiceLanguage,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(strings.voiceLanguageAuto),
                ),
                DropdownMenuItem(
                  value: 'zh',
                  child: Text(strings.voiceLanguageChinese),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Text(strings.voiceLanguageEnglish),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => voiceLanguage = value);
                widget.onVoiceLanguageChanged(value);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _info(strings.settingsSavedLocally),
    ],
  );

  Widget _storage(AppLocalizations strings) {
    final usageFuture = storageUsage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(strings.storage, strings.mobileSettingsDescription),
        if (usageFuture == null)
          const SizedBox.shrink()
        else
          FutureBuilder<_StorageUsage>(
            future: usageFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final usage = snapshot.data!;
              return _panel(
                children: [
                  _usageTile(strings.appData, usage.appData),
                  _usageTile(strings.temporaryFiles, usage.temporaryFiles),
                  const Divider(height: 12),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(strings.clearTemporaryFiles),
                    subtitle: Text(strings.clearTemporaryFilesHint),
                    onTap: usage.temporaryFiles == 0
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await clearTemporaryFiles();
                            if (!mounted) return;
                            setState(() => storageUsage = readStorageUsage());
                            messenger.showSnackBar(
                              SnackBar(content: Text(strings.storageCleared)),
                            );
                          },
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() => storageUsage = readStorageUsage()),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: Text(strings.refreshStorage),
        ),
      ],
    );
  }

  Widget _usageTile(String title, int bytes) => ListTile(
    leading: const Icon(Icons.data_usage_outlined),
    title: Text(title),
    trailing: Text(
      formatBytes(bytes),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  Widget _configuration(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.configuration, strings.computerSettingsDescription),
      _panel(
        children: [
          ListTile(
            leading: const Icon(Icons.route_outlined),
            title: Text(strings.defaultMode),
            trailing: DropdownButton<String>(
              value: widget.mode,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'default',
                  child: Text(strings.defaultMode),
                ),
                DropdownMenuItem(value: 'plan', child: Text(strings.planMode)),
              ],
              onChanged: (value) {
                if (value != null) widget.onModeChanged(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: Text(strings.effort),
            subtitle: Text(strings.desktopManagedHint),
            trailing: _effortDropdown(strings),
          ),
        ],
      ),
    ],
  );

  Widget _effortDropdown(AppLocalizations strings) {
    final selected = widget.models
        .whereType<Map>()
        .where(
          (value) =>
              value['model'] == widget.selectedModel ||
              value['id'] == widget.selectedModel,
        )
        .firstOrNull;
    final efforts = (selected?['supportedReasoningEfforts'] as List? ?? [])
        .map(
          (value) => value is Map
              ? value['reasoningEffort']?.toString()
              : value?.toString(),
        )
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    if (efforts.isEmpty) {
      return Text(widget.selectedEffort ?? strings.defaultMode);
    }
    return DropdownButton<String>(
      value: efforts.contains(widget.selectedEffort)
          ? widget.selectedEffort
          : null,
      hint: Text(widget.selectedEffort ?? strings.effort),
      underline: const SizedBox.shrink(),
      items: [
        for (final value in efforts)
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: widget.onEffortChanged,
    );
  }

  Widget _personalization(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.personalization, strings.computerSettingsDescription),
      _panel(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(strings.personalization),
            subtitle: Text(strings.desktopManagedHint),
            trailing: DropdownButton<String>(
              value: widget.responseStyle,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'none',
                  child: Text(strings.responseStyleNone),
                ),
                DropdownMenuItem(
                  value: 'friendly',
                  child: Text(strings.responseStyleFriendly),
                ),
                DropdownMenuItem(
                  value: 'pragmatic',
                  child: Text(strings.responseStylePragmatic),
                ),
              ],
              onChanged: (value) {
                if (value != null) widget.onResponseStyleChanged(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(strings.responseStyle),
            subtitle: Text(strings.responseStyleHint),
          ),
        ],
      ),
    ],
  );

  Widget _git(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.git, strings.computerSettingsDescription),
      _panel(
        children: [
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(strings.currentWorkspace),
            subtitle: Text(_selectedProjectLabel(strings)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(strings.git),
            subtitle: Text(strings.desktopSettingsReadOnly),
          ),
        ],
      ),
    ],
  );

  Widget _worktrees(AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(strings.worktrees, strings.computerSettingsDescription),
      if (widget.projects.isEmpty)
        _panel(children: [ListTile(title: Text(strings.noWorkspace))])
      else
        _panel(
          children: [
            for (final project in widget.projects.whereType<Map>())
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(
                  project['label']?.toString() ??
                      project['projectId']?.toString() ??
                      strings.noWorkspace,
                ),
                subtitle: project['branch'] == null
                    ? null
                    : Text(project['branch'].toString()),
                trailing: project['projectId'] == widget.selectedProjectId
                    ? const Icon(Icons.check_rounded, size: 19)
                    : null,
                onTap: project['projectId'] is String
                    ? () => widget.onProjectChanged(
                        project['projectId'] as String,
                      )
                    : null,
              ),
          ],
        ),
    ],
  );

  String _selectedProjectLabel(AppLocalizations strings) {
    final project = widget.projects
        .whereType<Map>()
        .where((value) => value['projectId'] == widget.selectedProjectId)
        .firstOrNull;
    return project?['label']?.toString() ??
        widget.selectedProjectId ??
        strings.noWorkspace;
  }

  Widget _info(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.35,
      ),
    ),
  );

  Future<_StorageUsage> readStorageUsage() async {
    try {
      final app = await getApplicationSupportDirectory();
      final temporary = await getTemporaryDirectory();
      return _StorageUsage(
        appData: await directorySize(app),
        temporaryFiles: await directorySize(temporary),
      );
    } catch (_) {
      return const _StorageUsage(appData: 0, temporaryFiles: 0);
    }
  }

  Future<void> clearTemporaryFiles() async {
    final directory = await getTemporaryDirectory();
    if (!await directory.exists()) return;
    for (final entity in directory.listSync()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }
}

class _StorageUsage {
  const _StorageUsage({required this.appData, required this.temporaryFiles});
  final int appData, temporaryFiles;
}

Future<int> directorySize(Directory directory) async {
  if (!await directory.exists()) return 0;
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {}
    }
  }
  return total;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
  const _ApprovalRow({
    required this.strings,
    required this.request,
    required this.onTap,
  });
  final AppLocalizations strings;
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
                      ? strings.inputNeeded
                      : strings.approvalRequired,
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
    super.key,
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
      constraints: const BoxConstraints(minHeight: 27, maxWidth: 180),
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
            borderRadius: BorderRadius.circular(12),
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
            isExpanded: false,
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
    required this.strings,
    required this.projectLabel,
    required this.branchLabel,
    required this.locationLabel,
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
  final AppLocalizations strings;
  final String? projectLabel, branchLabel, locationLabel;
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
    final contextItems = <({IconData icon, String label})>[
      if (projectLabel != null && projectLabel!.trim().isNotEmpty)
        (icon: Icons.folder_outlined, label: projectLabel!.trim()),
      if (locationLabel != null && locationLabel!.trim().isNotEmpty)
        (icon: Icons.computer_outlined, label: locationLabel!.trim()),
      if (branchLabel != null && branchLabel!.trim().isNotEmpty)
        (icon: Icons.account_tree_outlined, label: branchLabel!.trim()),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
      child: Container(
        key: const ValueKey('composer-shell'),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (contextItems.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 3),
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < contextItems.length;
                      index++
                    ) ...[
                      if (index > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: _muted,
                          ),
                        ),
                      Icon(
                        contextItems[index].icon,
                        size: 15,
                        color: const Color(0xff5d5e59),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        contextItems[index].label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff454641),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            TextField(
              controller: input,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(13, 7, 13, 9),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 7, 7),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _ComposerSelect(
                      value: mode,
                      leading: Icons.route_outlined,
                      labels: {
                        'default': strings.defaultMode,
                        'plan': strings.planMode,
                      },
                      onChanged: onModeChanged,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ComposerSelect(
                            key: const ValueKey('model-select'),
                            value: selectedModel,
                            labels: {
                              for (final value in availableModels) value: value,
                            },
                            onChanged: onModelChanged,
                          ),
                          if (efforts.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            _ComposerSelect(
                              value: effort,
                              labels: {
                                for (final value in efforts) value: value,
                              },
                              placeholder: strings.effort,
                              onChanged: onEffortChanged,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (running && onStop != null)
                    IconButton(
                      tooltip: strings.stop,
                      onPressed: busy ? null : onStop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 31,
                        height: 31,
                      ),
                    ),
                  IconButton.filled(
                    tooltip: running ? strings.steer : strings.send,
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
            ),
          ],
        ),
      ),
    );
  }
}
