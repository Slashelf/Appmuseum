import 'package:flutter/material.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import '../core/navigation/place_route.dart';
import '../core/theme/app_theme.dart';
import '../models/object_model.dart';
import 'home_screen.dart';
import 'app_localizations.dart';
import 'gallery_viewer.dart';
import 'guide_prose.dart';
import 'place_audio_bar.dart';

class ObjectDetailAdvancedScreen extends StatefulWidget {
  final ObjectModel object;
  const ObjectDetailAdvancedScreen({super.key, required this.object});

  @override
  State<ObjectDetailAdvancedScreen> createState() =>
      _ObjectDetailAdvancedScreenState();
}

class _ObjectDetailAdvancedScreenState
    extends State<ObjectDetailAdvancedScreen> {
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final t = AppLocalizations.of(context);
    final object = widget.object.localized(
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      backgroundColor: GuidePalette.background,
      floatingActionButton: FloatingActionButton(
        elevation: 0,
        backgroundColor: GuidePalette.surface,
        child: const Icon(Icons.arrow_back, color: GuidePalette.accent),
        onPressed: () => Navigator.pop(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      body: Stack(
        children: [
          // IMAGEN PRINCIPAL
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SizedBox(
              height: size.height * 0.43,
              child: Hero(
                tag: '${object.id}-more',
                child: GalleryImage(
                  path: object.imageUrl2.trim().isEmpty ? object.imageUrl : object.imageUrl2,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          // TARJETA BLANCA INFERIOR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: size.height * 0.60,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              decoration: const BoxDecoration(
                color: GuidePalette.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- SALOMON BOTTOM BAR COMO PESTAÑAS ---
                  SalomonBottomBar(
                    currentIndex: selectedTab,
                    onTap: (index) {
                      setState(() {
                        selectedTab = index;
                      });
                    },
                    selectedItemColor: GuidePalette.accent,
                    unselectedItemColor: Colors.grey[400],
                    items: [
                      SalomonBottomBarItem(
                        icon: const Icon(Icons.info_outline),
                        title: Text(t.get('detailsTab') ?? "Detalles"),
                        selectedColor: GuidePalette.accent,
                      ),
                      SalomonBottomBarItem(
                        icon: const Icon(Icons.photo_library_outlined),
                        title: Text(t.get('galleryTab') ?? "Galería"),
                        selectedColor: GuidePalette.accent,
                      ),
                      SalomonBottomBarItem(
                        icon: const Icon(Icons.article_outlined),
                        title: Text(t.get('infoTab') ?? "Información"),
                        selectedColor: GuidePalette.accent,
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    object.name2,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: GuidePalette.ink,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // --- CONTENIDO DINÁMICO SEGÚN PESTAÑA ---
                  Expanded(
                    child: IndexedStack(
                      index: selectedTab,
                      children: [
                        // DETALLES
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PlaceAudioBar(
                                placeId: object.id,
                                spokenText: object.cryptDescription.trim().isNotEmpty
                                    ? object.cryptDescription
                                    : object.description,
                                languageCode: Localizations.localeOf(context).languageCode,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                t.get('objectDescription'),
                                style: AppFonts.display(
                                  fontSize: 26,
                                  color: GuidePalette.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GuideProse(
                                text: object.cryptDescription.trim().isNotEmpty
                                    ? object.cryptDescription
                                    : object.description,
                                style: AppFonts.poppins(
                                  fontSize: 15,
                                  height: 1.45,
                                  color: GuidePalette.ink,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // GALERÍA
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: object.galleryImages.isEmpty
                              ? Center(
                                  child: Text(
                                    t.get('noImages') ?? "No hay imágenes",
                                    style: const TextStyle(
                                      color: GuidePalette.muted,
                                    ),
                                  ),
                                )
                              : GridView.builder(
                                  itemCount: object.galleryImages.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    childAspectRatio: 0.78,
                                  ),
                                  itemBuilder: (context, index) {
                                    return GalleryThumb(
                                      path: object.galleryImages[index],
                                      onTap: () => GalleryViewer.open(
                                        context,
                                        object.galleryImages,
                                        index,
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // INFO EXTRA
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.get('infoTitle'),
                                style: AppFonts.display(
                                  fontSize: 26,
                                  color: GuidePalette.ink,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _fact(t.get('locationLabel'), object.location, t.get('notAvailable')),
                              _fact(t.get('addressLabel'), object.direccion, t.get('notAvailable')),
                              _fact(t.get('phoneLabel'), object.celular, t.get('notAvailable')),
                              _fact(t.get('hoursLabel'), object.openingHours, t.get('notAvailable')),
                              _fact(
                                t.get('yearFoundedLabel'),
                                object.yearFounded?.toString(),
                                t.get('unknown'),
                              ),
                              _fact(
                                t.get('architecturalStyleLabel'),
                                object.architecturalStyle,
                                t.get('unknown'),
                              ),
                              _fact(t.get('entranceFeeLabel'), object.entranceFee, t.get('notAvailable')),
                              _fact(t.get('categoryLabel'), object.category, t.get('notAvailable')),
                              const SizedBox(height: 6),
                              Text(
                                t.get('historicalNotesLabel'),
                                style: AppFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: GuidePalette.accent,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 6),
                              GuideProse(
                                text: (object.historicalNotes ?? '').trim().isEmpty
                                    ? t.get('notAvailable')
                                    : object.historicalNotes!,
                                style: AppFonts.poppins(
                                  fontSize: 15,
                                  height: 1.45,
                                  color: GuidePalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  PlaceRouteButton(address: object.direccion),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MainScreen(showTutorial: false),
                            ),
                          );
                        },
                        child: _actionButton(t.get('goHome') ?? "Ir a Inicio"),
                      ),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _fact(String label, String? value, String fallback) {
    final text = (value == null || value.trim().isEmpty) ? fallback : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GuidePalette.accent,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: AppFonts.poppins(
              fontSize: 15,
              height: 1.35,
              color: GuidePalette.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String title) {
    return Container(
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
        title,
        style: AppFonts.poppins(
          color: GuidePalette.onAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
