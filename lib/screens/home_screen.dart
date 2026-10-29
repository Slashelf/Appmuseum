import 'dart:async';
import 'package:flutter/material.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import 'home_tab.dart';
import 'content_screen.dart';
import 'contact_form.dart';
import 'object_detail_screen.dart';
import 'qr_scan_screen.dart';
import 'nfc_scan_services.dart';
import 'beacon_scan_services.dart';
import 'chat_screen.dart';
import '../core/beacons/beacon_config.dart';
import '../core/location/location_gate.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';
import 'guide_drawer.dart';
class MainScreen extends StatefulWidget {
  final bool showTutorial;
  final Future<bool> Function()? locationServicesOn;
  final Future<void> Function()? openLocationSettings;

  const MainScreen({
    super.key,
    this.showTutorial = true,
    this.locationServicesOn,
    this.openLocationSettings,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final List<Widget> _tabs = [
    HomeTab(),
    ExplorarTab(),
    ContactForm(),
  ];

  // --- NFC ---
  bool isNfcActive = false;
  Timer? _blinkTimer;
  bool _showNfcIcon = true;

  // --- BEACON ---
  bool isBeaconActive = false;
  final beaconService = BeaconServiceFlutter();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- Tutorial ---
 // --- Tutorial Overlay ---
  bool showBeaconTutorial = true; // Siempre inicia en true
  bool _locationOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    showBeaconTutorial = widget.showTutorial;
    _checkLocation();
    isBeaconActive = beaconService.enabled;
    beaconService.bindFound((obj) {
      if (!mounted) return;
      openDetectedPlace(context, obj);
    });
    beaconService.addEnabledListener(_onBeaconEnabled);
  }

  void _onBeaconEnabled(bool active) {
    if (!mounted) return;
    setState(() => isBeaconActive = active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    beaconService.removeEnabledListener(_onBeaconEnabled);
    _blinkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    final probe = widget.locationServicesOn ?? LocationGate.servicesOn;
    var on = true;
    try {
      on = await probe();
    } catch (_) {
      on = true;
    }
    if (!mounted) return;
    setState(() => _locationOff = !on);
  }

  Future<void> _openLocation() async {
    final open = widget.openLocationSettings ?? LocationGate.openSettings;
    try {
      await open();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocation();
      if (isBeaconActive) beaconService.resumeScan();
      return;
    }
    if (!isBeaconActive) return;
    if (state == AppLifecycleState.paused) {
      beaconService.pauseScan();
    }
  }

  void _acceptTutorial() {
    setState(() {
      showBeaconTutorial = false; // Solo ocultar mientras está en MainScreen
    });
  }



  void _toggleBeacon() async {
    if (isBeaconActive) {
      await beaconService.stopScan();
      setState(() => isBeaconActive = false);
    } else {
      final t = AppLocalizations.of(context);
      await beaconService.startScan(
        iBeaconUUIDs: const [BeaconConfig.uuid],
        permissionDeniedMessage: t.get('blePermissionDenied'),
        onObjectFound: (obj) {
          if (!mounted) return;
          openDetectedPlace(context, obj);
        },
        onMessage: (msg) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        },
      );
      if (!mounted) return;
      setState(() => isBeaconActive = beaconService.scanning);
    }
  }

  void _startBlinking() {
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _showNfcIcon = !_showNfcIcon);
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    setState(() => _showNfcIcon = true);
  }

  void _toggleNfc() {
    if (!isNfcActive) {
      setState(() => isNfcActive = true);
      _startBlinking();
      final t = AppLocalizations.of(context);
      NfcService.startNfcSession(
        iosAlert: t.get('nfcIosAlert'),
        onObjectFound: (obj) {
          if (!mounted) return;
          openDetectedPlace(context, obj);
        },
        onMessage: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_nfcMessage(message))),
          );
        },
      );
    } else {
      NfcService.stopNfcSession();
      setState(() => isNfcActive = false);
      _stopBlinking();
    }
  }

  String _nfcMessage(String message) {
    final t = AppLocalizations.of(context);
    const keys = {'nfcNoNdef', 'nfcUnknown', 'nfcNoRecords'};
    if (keys.contains(message)) return t.get(message);
    if (message.startsWith('nfcReadError:')) {
      return '${t.get('nfcReadError')} ${message.substring('nfcReadError:'.length)}';
    }
    return message;
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context); // <- Traducciones

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: GuidePalette.background,
      drawer: GuideDrawer(
        beaconOn: isBeaconActive,
        nfcOn: isNfcActive,
        onBeacon: _toggleBeacon,
        onNfc: _toggleNfc,
        onChat: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: GuideRoutes.chat),
              builder: (_) => const ChatScreen(),
            ),
          );
        },
        onQr: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QRScanScreen()),
          );
        },
      ),
      body: Stack(
        children: [
          _tabs[_selectedIndex],
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.only(top: 36, left: 4, right: 16, bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, color: GuidePalette.accent),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                    child: Text(
                      t.get('mintApp'),
                      style: AppFonts.display(
                        fontSize: 28,
                        color: GuidePalette.ink,
                      ),
                    ),
                  ),
                  if (isBeaconActive)
                    const Icon(Icons.bluetooth_searching, color: GuidePalette.accent, size: 20),
                ],
              ),
            ),
          ),
          if (_locationOff)
            Positioned(
              top: 86,
              left: 12,
              right: 12,
              child: Material(
                color: GuidePalette.surface,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.get('locationOff'),
                          key: const Key('location-off'),
                          style: AppFonts.poppins(
                            color: GuidePalette.ink,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('location-on'),
                        onPressed: _openLocation,
                        child: Text(t.get('locationTurnOn')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (showBeaconTutorial)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                decoration: BoxDecoration(
                  color: GuidePalette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: GuidePalette.accent),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.get('beaconTutorial'),
                      textAlign: TextAlign.center,
                      style: AppFonts.poppins(
                        color: GuidePalette.ink,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _acceptTutorial,
                      child: Text(
                        t.get('understood'),
                        style: AppFonts.poppins(
                          color: GuidePalette.accent,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        child: SalomonBottomBar(
          currentIndex: _selectedIndex,
          selectedItemColor: GuidePalette.accent,
          unselectedItemColor: GuidePalette.muted,
          onTap: _onItemTapped,
          items: [
            SalomonBottomBarItem(
              icon: const Icon(Icons.home),
              title: Text(t.get('home')),
              selectedColor: GuidePalette.accent,
            ),
            SalomonBottomBarItem(
              icon: const Icon(Icons.explore),
              title: Text(t.get('explore')),
              selectedColor: GuidePalette.accent,
            ),
            SalomonBottomBarItem(
              icon: const Icon(Icons.contact_mail),
              title: Text(t.get('contact')),
              selectedColor: GuidePalette.accent,
            ),
          ],
        ),
      ),
    );
  }
}
