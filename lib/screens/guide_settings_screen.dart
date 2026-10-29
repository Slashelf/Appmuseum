import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_faq.dart';
import '../chat/connection_check.dart';
import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

/// Claves y prueba de conexión. La clave compilada oculta su campo.
class GuideSettingsScreen extends StatefulWidget {
  const GuideSettingsScreen({super.key});

  @override
  State<GuideSettingsScreen> createState() => _GuideSettingsScreenState();
}

class _GuideSettingsScreenState extends State<GuideSettingsScreen> {
  final TextEditingController _deepSeek = TextEditingController();
  final TextEditingController _eleven = TextEditingController();
  final TextEditingController _voice = TextEditingController();
  String _deepResult = '';
  String _elevenResult = '';
  bool _deepBusy = false;
  bool _elevenBusy = false;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    final chat = context.read<ChatController>();
    if (!chat.hasCompiledKey) _deepSeek.text = chat.runtimeKey;
    if (!chat.hasCompiledElevenKey) _eleven.text = chat.elevenRuntimeKey;
    _voice.text = chat.elevenVoiceId;
    _filled = true;
    _fillResolvedVoice(chat);
  }

  Future<void> _fillResolvedVoice(ChatController chat) async {
    if (_voice.text.trim().isNotEmpty) return;
    final id = await chat.ensureNarratorVoice();
    if (!mounted || id.trim().isEmpty || _voice.text.trim().isNotEmpty) return;
    setState(() => _voice.text = id.trim());
  }

  @override
  void dispose() {
    _deepSeek.dispose();
    _eleven.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final chat = context.watch<ChatController>();
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
          else
            _secretField(
              key: const Key('chat-settings-deepseek'),
              label: t.get('settingsDeepSeek'),
              controller: _deepSeek,
              onChanged: chat.updateDeepSeekKey,
            ),
          const SizedBox(height: 8),
          _probeButton(
            key: const Key('chat-test-deepseek'),
            label: t.get('settingsTestConnection'),
            busy: _deepBusy,
            onPressed: () => _testDeepSeek(chat, t),
          ),
          if (_deepResult.isNotEmpty)
            _result(const Key('chat-test-deepseek-result'), _deepResult),
          const SizedBox(height: 20),
          if (chat.hasCompiledElevenKey)
            _note(t.get('settingsCompiled'))
          else
            _secretField(
              key: const Key('chat-settings-eleven'),
              label: t.get('settingsEleven'),
              controller: _eleven,
              onChanged: chat.updateElevenKey,
            ),
          const SizedBox(height: 8),
          _probeButton(
            key: const Key('chat-test-eleven'),
            label: t.get('settingsTestVoice'),
            busy: _elevenBusy,
            onPressed: () => _testEleven(chat, t),
          ),
          if (_elevenResult.isNotEmpty)
            _result(const Key('chat-test-eleven-result'), _elevenResult),
          const SizedBox(height: 20),
          _secretField(
            key: const Key('chat-settings-voice'),
            label: t.get('settingsVoice'),
            controller: _voice,
            onChanged: chat.updateVoiceId,
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

  Widget _result(Key key, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: key,
        style: AppFonts.poppins(fontSize: 13, height: 1.35, color: GuidePalette.ink),
      ),
    );
  }

  Future<void> _testDeepSeek(ChatController chat, AppLocalizations t) async {
    final language = context.read<LocaleController>().locale.languageCode;
    if (chat.deepSeekKey.isEmpty) {
      setState(() => _deepResult = ChatFaq.missingKey(language));
      return;
    }
    setState(() {
      _deepBusy = true;
      _deepResult = '';
    });
    final ConnectionReport report = await chat.connections.deepSeek(chat.deepSeekKey);
    if (!mounted) return;
    setState(() {
      _deepBusy = false;
      _deepResult = report.ok ? t.get('settingsConnected') : report.message;
    });
  }

  Future<void> _testEleven(ChatController chat, AppLocalizations t) async {
    if (chat.elevenKey.isEmpty) {
      setState(() => _elevenResult = t.get('elevenKeyMissing'));
      return;
    }
    setState(() {
      _elevenBusy = true;
      _elevenResult = '';
    });
    final ConnectionReport report = await chat.connections.elevenLabs(chat.elevenKey);
    if (!mounted) return;
    setState(() {
      _elevenBusy = false;
      _elevenResult = report.ok ? t.get('settingsConnected') : report.message;
    });
  }
}
