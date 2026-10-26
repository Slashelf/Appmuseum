import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

class GuideDrawer extends StatelessWidget {
  final bool beaconOn;
  final bool nfcOn;
  final VoidCallback onBeacon;
  final VoidCallback onNfc;
  final VoidCallback onChat;
  final VoidCallback onQr;

  const GuideDrawer({
    super.key,
    required this.beaconOn,
    required this.nfcOn,
    required this.onBeacon,
    required this.onNfc,
    required this.onChat,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final code = context.watch<LocaleController>().locale.languageCode;
    final locales = context.read<LocaleController>();

    return Drawer(
      backgroundColor: GuidePalette.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(
              t.get('mintApp'),
              style: AppFonts.display(
                fontSize: 34,
                color: GuidePalette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.get('onBoardingSubtitle').split('\n').first,
              style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
            ),
            const SizedBox(height: 28),
            _Section(t.get('language')),
            _LanguageTile(
              label: t.get('spanish'),
              selected: code == 'es',
              onTap: () => _choose(context, () => locales.setLocale(const Locale('es'))),
            ),
            _LanguageTile(
              label: t.get('english'),
              selected: code == 'en',
              onTap: () => _choose(context, () => locales.setLocale(const Locale('en'))),
            ),
            _LanguageTile(
              label: t.get('german'),
              selected: code == 'de',
              onTap: () => _choose(context, () => locales.setLocale(const Locale('de'))),
            ),
            const SizedBox(height: 18),
            _Section(t.get('menuVisit')),
            _RowTile(
              icon: Icons.bluetooth_searching,
              label: t.get('beaconLabel'),
              trailing: beaconOn ? t.get('beaconOn') : t.get('beaconOff'),
              active: beaconOn,
              onTap: () => _choose(context, onBeacon),
            ),
            _RowTile(
              icon: Icons.chat_bubble_outline,
              label: t.get('chatMenu'),
              onTap: () => _choose(context, onChat),
            ),
            const SizedBox(height: 18),
            _Section(t.get('menuArrive')),
            _RowTile(
              icon: Icons.qr_code_scanner,
              label: t.get('qrScan'),
              onTap: () => _choose(context, onQr),
            ),
            _RowTile(
              icon: Icons.nfc,
              label: t.get('nfcScan'),
              trailing: nfcOn ? t.get('beaconOn') : t.get('beaconOff'),
              active: nfcOn,
              onTap: () => _choose(context, onNfc),
            ),
          ],
        ),
      ),
    );
  }

  void _choose(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: GuidePalette.accent,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: AppFonts.poppins(color: GuidePalette.ink, fontSize: 16)),
      trailing: selected ? const Icon(Icons.check, color: GuidePalette.accent, size: 18) : null,
      onTap: onTap,
    );
  }
}

class _RowTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool active;
  final VoidCallback onTap;

  const _RowTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = active ? GuidePalette.accent : GuidePalette.ink;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: tone),
      title: Text(label, style: AppFonts.poppins(color: tone, fontSize: 16)),
      trailing: trailing == null
          ? null
          : Text(
              trailing!,
              style: AppFonts.poppins(
                color: active ? GuidePalette.accent : GuidePalette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: onTap,
    );
  }
}
