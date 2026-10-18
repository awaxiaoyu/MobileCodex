import 'package:flutter/material.dart';

/// Small app-owned localization layer. It keeps product copy independent from
/// Flutter's Material defaults and does not require a generated intl package.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh')];
  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  bool get isChinese => locale.languageCode.toLowerCase() == 'zh';

  String t(String key, {Map<String, String> args = const {}}) {
    final value = (isChinese ? _zh : _en)[key] ?? key;
    return args.entries.fold(value, (text, entry) {
      return text.replaceAll('{${entry.key}}', entry.value);
    });
  }

  String get chats => t('chats');
  String get pinned => t('pinned');
  String get projects => t('projects');
  String get conversations => t('conversations');
  String get noPinnedChats => t('noPinnedChats');
  String get noProjectChats => t('noProjectChats');
  String get noConversations => t('noConversations');
  String get defaultMode => t('defaultMode');
  String get planMode => t('planMode');
  String get effort => t('effort');
  String get messageCodex => t('messageCodex');
  String get addDirection => t('addDirection');
  String get chat => t('chat');
  String get settings => t('settings');
  String get connectedComputer => t('connectedComputer');
  String get local => t('local');
  String get preferences => t('preferences');
  String get connected => t('connected');
  String get running => t('running');
  String get stop => t('stop');
  String get send => t('send');
  String get steer => t('steer');
  String get assistant => t('assistant');
  String get you => t('you');
  String get noContent => t('noContent');
  String get reviewDiff => t('reviewDiff');
  String get planFeature => t('planFeature');
  String get fixBug => t('fixBug');
  String get welcomeTitle => t('welcomeTitle');
  String get openMenu => t('openMenu');
  String get chatActions => t('chatActions');
  String get pin => t('pin');
  String get unpin => t('unpin');
  String get untitledChat => t('untitledChat');
  String get newChat => t('newChat');
  String get computerDisconnected => t('computerDisconnected');
  String get desktopOffline => t('desktopOffline');
  String get taskSubmitted => t('taskSubmitted');
  String get ownAnswer => t('ownAnswer');
  String get later => t('later');
  String get submit => t('submit');
  String get approvalRequired => t('approvalRequired');
  String get additionalPermissions => t('additionalPermissions');
  String get decline => t('decline');
  String get allowThisTime => t('allowThisTime');
  String get allowCurrentTask => t('allowCurrentTask');
  String get formRequired => t('formRequired');
  String get unsupportedApproval => t('unsupportedApproval');
  String get unsupportedInteraction => t('unsupportedInteraction');
  String get connectComputer => t('connectComputer');
  String get pairingInfo => t('pairingInfo');
  String get cancel => t('cancel');
  String get pair => t('pair');
  String get scanPairingCode => t('scanPairingCode');
  String get scanPairingTitle => t('scanPairingTitle');
  String get scanPairingHint => t('scanPairingHint');
  String get cameraUnavailable => t('cameraUnavailable');
  String get taskDiff => t('taskDiff');
  String get working => t('working');
  String get viewArtifacts => t('viewArtifacts');
  String get refresh => t('refresh');
  String get openChatList => t('openChatList');
  String get inputNeeded => t('inputNeeded');
  String get fillAnswer => t('fillAnswer');
  String get checkRequestResult => t('checkRequestResult');
  String get invalidNumber => t('invalidNumber');
  String get notConnected => t('notConnected');
  String get connecting => t('connecting');
  String get disconnected => t('disconnected');
  String get connectionFailed => t('connectionFailed');
  String get deviceRevoked => t('deviceRevoked');

  static const _en = <String, String>{
    'chats': 'Chats',
    'pinned': 'Pinned',
    'projects': 'Projects',
    'conversations': 'Conversations',
    'noPinnedChats': 'No pinned chats',
    'noProjectChats': 'No project chats',
    'noConversations': 'No conversations',
    'defaultMode': 'Default',
    'planMode': 'Plan',
    'effort': 'Effort',
    'messageCodex': 'Message Codex…',
    'addDirection': 'Add direction to this task…',
    'chat': 'Chat',
    'settings': 'Settings',
    'connectedComputer': 'Connected computer',
    'local': 'Local',
    'preferences': 'Preferences',
    'connected': 'Connected',
    'running': 'Running',
    'stop': 'Stop',
    'send': 'Send',
    'steer': 'Steer',
    'assistant': 'Codex',
    'you': 'You',
    'noContent': 'No visible content',
    'reviewDiff': 'Review a diff',
    'planFeature': 'Plan a feature',
    'fixBug': 'Fix a bug',
    'welcomeConnected': 'Start a task with your connected workspace.',
    'welcomeDisconnected': 'Connect a computer to get started',
    'welcomeTitle': 'What are we building today?',
    'openMenu': 'Open navigation menu',
    'chatActions': 'Chat actions',
    'pin': 'Pin',
    'unpin': 'Unpin',
    'untitledChat': 'Untitled chat',
    'newChat': 'New chat',
    'computerDisconnected': 'Bridge is not connected to Codex Desktop',
    'desktopOffline': 'Desktop offline',
    'taskSubmitted': 'Task submitted',
    'ownAnswer': 'Your answer',
    'later': 'Later',
    'submit': 'Submit',
    'approvalRequired': 'Approval required',
    'additionalPermissions': 'Additional permissions',
    'decline': 'Decline',
    'allowThisTime': 'Allow this time',
    'allowCurrentTask': 'Allow for this task',
    'formRequired': 'This task needs information',
    'unsupportedApproval': 'Complete this approval or form on your computer',
    'unsupportedInteraction': 'Complete this interaction on your computer',
    'connectComputer': 'Connect computer',
    'pairingInfo': 'Paste the pairing information from your computer',
    'cancel': 'Cancel',
    'pair': 'Pair',
    'scanPairingCode': 'Scan QR code',
    'scanPairingTitle': 'Scan pairing QR code',
    'scanPairingHint':
        'Point your camera at the QR code shown on your computer.',
    'cameraUnavailable':
        'Camera access is unavailable. Check camera permission and try again.',
    'taskDiff': 'Task diff',
    'working': 'Working on the task',
    'viewArtifacts': 'View artifacts',
    'refresh': 'Refresh',
    'openChatList': 'Open chat list',
    'inputNeeded': 'Input needed to continue',
    'fillAnswer': 'Answer required: {field}',
    'checkRequestResult': 'Check the previous request result',
    'invalidNumber': '{field} must be a number',
    'notConnected': 'Not connected',
    'connecting': 'Connecting',
    'disconnected': 'Connection interrupted',
    'connectionFailed': 'Connection failed',
    'deviceRevoked': 'Device revoked; pair again',
  };

  static const _zh = <String, String>{
    'chats': '聊天',
    'pinned': '置顶',
    'projects': '项目',
    'conversations': '对话',
    'noPinnedChats': '暂无置顶聊天',
    'noProjectChats': '暂无项目聊天',
    'noConversations': '暂无对话',
    'defaultMode': '默认',
    'planMode': '计划',
    'effort': '推理强度',
    'messageCodex': '给 Codex 发消息…',
    'addDirection': '继续指导这个任务…',
    'chat': '聊天',
    'settings': '设置',
    'connectedComputer': '已连接电脑',
    'local': '本地',
    'preferences': '偏好设置',
    'connected': '已连接',
    'running': '运行中',
    'stop': '停止',
    'send': '发送',
    'steer': '指导',
    'assistant': 'Codex',
    'you': '你',
    'noContent': '暂无可显示内容',
    'reviewDiff': '查看差异',
    'planFeature': '规划功能',
    'fixBug': '修复问题',
    'welcomeConnected': '从已连接的工作区开始任务。',
    'welcomeDisconnected': '连接电脑后开始使用',
    'welcomeTitle': '今天要一起构建什么？',
    'openMenu': '打开聊天菜单',
    'chatActions': '聊天操作',
    'pin': '置顶',
    'unpin': '取消置顶',
    'untitledChat': '未命名聊天',
    'newChat': '新聊天',
    'computerDisconnected': 'Bridge 尚未连接 Codex Desktop',
    'desktopOffline': '电脑端未连接',
    'taskSubmitted': '任务已提交',
    'ownAnswer': '你的回答',
    'later': '稍后',
    'submit': '提交',
    'approvalRequired': '任务需要审批',
    'additionalPermissions': '额外权限',
    'decline': '拒绝',
    'allowThisTime': '允许这次',
    'allowCurrentTask': '允许当前任务',
    'formRequired': '任务需要填写信息',
    'unsupportedApproval': '此授权或表单请到电脑完成',
    'unsupportedInteraction': '此交互请到电脑完成，手机表单尚未适配',
    'connectComputer': '连接电脑',
    'pairingInfo': '粘贴电脑生成的配对信息',
    'cancel': '取消',
    'pair': '配对',
    'scanPairingCode': '扫描二维码',
    'scanPairingTitle': '扫描配对二维码',
    'scanPairingHint': '将相机对准电脑上显示的二维码。',
    'cameraUnavailable': '无法使用相机，请检查相机权限后重试。',
    'taskDiff': '任务差异',
    'working': '正在处理任务',
    'viewArtifacts': '查看生成文件',
    'refresh': '刷新',
    'openChatList': '打开聊天列表',
    'inputNeeded': '需要输入才能继续',
    'fillAnswer': '请填写 {field}',
    'checkRequestResult': '查看上一个请求的结果',
    'invalidNumber': '{field} 需要填写数字',
    'notConnected': '未连接',
    'connecting': '连接中',
    'disconnected': '连接中断',
    'connectionFailed': '连接失败',
    'deviceRevoked': '设备已撤销，请重新配对',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
