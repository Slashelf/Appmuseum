import 'package:flutter/material.dart';
import '../core/beacons/beacon_config.dart';
import '../core/navigation/place_navigation.dart';
import '../core/navigation/place_route.dart';
import '../core/theme/app_theme.dart';
import '../models/object_model.dart';
import 'app_localizations.dart';
import 'chat_screen.dart';
import 'gallery_viewer.dart';
import 'guide_drawer.dart';
import 'guide_prose.dart';
import 'place_audio_bar.dart';
import 'home_screen.dart';
import 'nfc_scan_services.dart';
import 'object_detail_add.dart';
import 'qr_scan_screen.dart';
import 'beacon_scan_services.dart';

void openDetectedPlace(BuildContext context, ObjectModel place) {
  openPlaceFromBeacon(
    context,
    place,
    placeRoute: (value) => MaterialPageRoute(
      settings: const RouteSettings(name: GuideRoutes.place),
      builder: (_) => ObjectDetailScreen(object: value),
    ),
  );
}

Future<void> _toggleDetailBeacon(BuildContext context) async {
  final beaconService = BeaconServiceFlutter();
  final t = AppLocalizations.of(context);
  if (beaconService.scanning || beaconService.enabled) {
    await beaconService.stopScan();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.get('beaconDeactivated'))),
    );
    return;
  }
  await beaconService.startScan(
    iBeaconUUIDs: const [BeaconConfig.uuid],
    permissionDeniedMessage: t.get('blePermissionDenied'),
    onObjectFound: (obj) {
      if (!context.mounted) return;
      openDetectedPlace(context, obj);
    },
    onMessage: (msg) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    },
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t.get('beaconActivated'))),
  );
}

void _toggleDetailNfc(BuildContext context) {
  final t = AppLocalizations.of(context);
  NfcService.startNfcSession(
    iosAlert: t.get('nfcIosAlert'),
    onObjectFound: (obj) {
      if (!context.mounted) return;
      openDetectedPlace(context, obj);
    },
    onMessage: (message) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    },
  );
}

class ObjectDetailScreen extends StatelessWidget {
  final ObjectModel object;
  const ObjectDetailScreen({super.key, required this.object});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final t = AppLocalizations.of(context);
    final shown = object.localized(
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      backgroundColor: GuidePalette.background,
      drawer: GuideDrawer(
        beaconOn: BeaconServiceFlutter().scanning || BeaconServiceFlutter().enabled,
        nfcOn: false,
        onBeacon: () => _toggleDetailBeacon(context),
        onNfc: () => _toggleDetailNfc(context),
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
          // --- IMAGEN PRINCIPAL ---
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SizedBox(
              height: size.height * 0.43,
              child: Hero(
                tag: shown.id,
                child: GalleryImage(
                  path: shown.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          // --- TARJETA BLANCA INFERIOR ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: size.height * 0.60,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              decoration: const BoxDecoration(
                color: GuidePalette.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: GuidePalette.accent)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shown.name,
                            style: AppFonts.display(
                              fontSize: 32,
                              color: GuidePalette.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          GuideProse(
                            text: shown.description,
                            style: AppFonts.poppins(
                              fontSize: 15,
                              height: 1.45,
                              color: GuidePalette.muted,
                            ),
                          ),
                          PlaceAudioBar(
                            placeId: shown.id,
                            spokenText: shown.description,
                            languageCode: Localizations.localeOf(context).languageCode,
                          ),
                          const SizedBox(height: 18),
                          if (shown.extraImages.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.get('gallery'),
                                  style: AppFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: GuidePalette.accent,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 148,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: shown.extraImages.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      return GalleryThumb(
                                        path: shown.extraImages[index],
                                        width: 108,
                                        height: 144,
                                        onTap: () => GalleryViewer.open(
                                          context,
                                          shown.extraImages,
                                          index,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PlaceRouteButton(address: shown.direccion),
                  const SizedBox(height: 10),

                  // BOTONES INFERIORES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Botón a Home
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MainScreen(showTutorial: false),
                            ),
                          );
                        },
                        child: Container(
                          width: 150,
                          height: 48,
                          decoration: BoxDecoration(
                            color: GuidePalette.accent,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            t.get('goHome') ?? "Ir a Inicio",
                            style: AppFonts.poppins(
                              color: GuidePalette.onAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Botón Ver más
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(name: GuideRoutes.place),
                              builder: (_) => ObjectDetailAdvancedScreen(object: shown),
                            ),
                          );
                        },
                        child: Container(
                          width: 150,
                          height: 48,
                          decoration: BoxDecoration(
                            color: GuidePalette.accent,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            t.get('seeMore'),
                            style: AppFonts.poppins(
                              color: GuidePalette.onAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Builder(
                builder: (buttonContext) => IconButton(
                  icon: const Icon(Icons.menu, color: GuidePalette.accent),
                  onPressed: () => Scaffold.of(buttonContext).openDrawer(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
