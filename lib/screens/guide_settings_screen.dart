import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_faq.dart';
import '../chat/connection_check.dart';
import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

/// Clave de Grok y elección de voz. La clave compilada oculta su campo.
class GuideSettingsScreen extends StatefulWidget {
  const GuideSettingsScreen({super.key});

  @override
  State<GuideSettingsScreen> createState() => _GuideSettingsScreenState();
}

class _GuideSettingsScreenState extends State<GuideSettingsScreen> {
  final TextEditingController _grok = TextEditingController();
  String _result = '';
  bool _busy = false;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    final chat = context.read<ChatController>();
    if (!chat.hasCompiledKey) _grok.text = chat.runtimeKey;
    _filled = true;
  }

  @override
  void dispose() {
    _grok.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final chat = context.watch<ChatController>();
    final woman = chat.guideVoice == 'ara';
    return Scaffold(
      backgroundColor: GuidePalette.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: GuidePalette.white,
        title: Text(
          t.get('settingsTitle'),
          style: AppFonts.poppins(
            color: GuidePalette.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (chat.hasCompiledKey)
            _note(t.get('settingsCompiled'))
          else ...[
            _secretField(
              key: const Key('chat-settings-grok'),
              label: t.get('settingsDeepSeek'),
              controller: _grok,
              onChanged: chat.updateDeepSeekKey,
            ),
            if (chat.runtimeKey.isNotEmpty) _note(t.get('settingsKeyUsed')),
          ],
          const SizedBox(height: 8),
          _probeButton(
            key: const Key('chat-test-grok'),
            label: t.get('settingsTestConnection'),
            busy: _busy,
            onPressed: () => _test(chat, t),
          ),
          if (_result.isNotEmpty) _resultText(const Key('chat-test-grok-result'), _result),
          const SizedBox(height: 20),
          Text(
            t.get('settingsVoice'),
            style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _voiceButton(
                key: const Key('chat-voice-woman'),
                label: t.get('voiceWoman'),
                selected: woman,
                onPressed: () => chat.updateVoiceId('ara'),
              ),
              const SizedBox(width: 8),
              _voiceButton(
                key: const Key('chat-voice-man'),
                label: t.get('voiceMan'),
                selected: !woman,
                onPressed: () => chat.updateVoiceId('leo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
      ),
    );
  }

  Widget _secretField({
    required Key key,
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      style: AppFonts.poppins(fontSize: 15, color: GuidePalette.ink),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
        filled: true,
        fillColor: GuidePalette.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GuidePalette.accent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GuidePalette.accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _probeButton({
    required Key key,
    required String label,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        key: key,
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: GuidePalette.ink,
          side: const BorderSide(color: GuidePalette.accent),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: GuidePalette.accent),
              )
            : Text(label, style: AppFonts.poppins(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _voiceButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? GuidePalette.background : GuidePalette.ink,
          backgroundColor: selected ? GuidePalette.accent : Colors.transparent,
          side: const BorderSide(color: GuidePalette.accent),
        ),
        child: Text(label, style: AppFonts.poppins(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _resultText(Key key, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: key,
        style: AppFonts.poppins(fontSize: 13, height: 1.35, color: GuidePalette.ink),
      ),
    );
  }

  Future<void> _test(ChatController chat, AppLocalizations t) async {
    final language = context.read<LocaleController>().locale.languageCode;
    if (chat.deepSeekKey.isEmpty) {
      setState(() => _result = ChatFaq.missingKey(language));
      return;
    }
    setState(() {
      _busy = true;
      _result = '';
    });
    final ConnectionReport report = await chat.connections.deepSeek(chat.deepSeekKey);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = report.ok ? t.get('settingsConnected') : report.message;
    });
  }
}
