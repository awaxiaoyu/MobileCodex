import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_codex/app_localizations.dart';

void main() {
  test('app copy is available in English and Chinese', () {
    expect(AppLocalizations(const Locale('en')).chats, 'Chats');
    expect(AppLocalizations(const Locale('zh')).chats, '聊天');
    expect(AppLocalizations(const Locale('zh')).noConversations, '暂无对话');
    expect(AppLocalizations(const Locale('en')).pin, 'Pin');
    expect(AppLocalizations(const Locale('zh')).pin, '置顶');
    expect(AppLocalizations(const Locale('en')).newChat, 'New chat');
  });
}
