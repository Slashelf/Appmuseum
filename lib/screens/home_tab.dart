import 'dart:async';

import 'package:flutter/material.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import '../models/object_model.dart';
import '../models/recommended_model.dart';
import '../utils/load_objects.dart';
import 'object_detail_screen.dart';
import 'recommended_widget.dart';
import 'app_localizations.dart'; // <- Tus traducciones

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<List<ObjectModel>> objectsFuture;
  late Future<List<RecommendedModel>> recommendedFuture;
  late Future<List<String>> carouselFuture;

  @override
  void initState() {
    super.initState();
    objectsFuture = loadObjects();
    recommendedFuture = loadRecommendedObjects();
    carouselFuture = loadObjectCarousel().then(
      (carousel) => carousel?.images ?? const <String>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context); // <- Traducciones

    return Container(
      color: Colors.transparent,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),

          // Banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<List<String>>(
                    future: carouselFuture,
                    builder: (context, snapshot) {
                      final images = (snapshot.data ?? const <String>[])
                          .where((path) => path.trim().isNotEmpty)
                          .toList();
                      return _HouseCarousel(
                        images: images.isEmpty
                            ? const ['assets/images/casa/fachada.jpg']
                            : images,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      t.get('homeBannerTitle'),
                      style: AppFonts.display(
                        fontSize: 32,
                        color: GuidePalette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      t.get('homeBannerSubtitle'),
                      style: AppFonts.poppins(fontSize: 15, height: 1.4, color: GuidePalette.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Sección Objetos
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 0, 12),
              child: Text(
                t.get('objectsSection') ?? 'Objetos',
                style: AppFonts.display(
                  color: GuidePalette.ink,
                  fontSize: 28,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 230,
              child: FutureBuilder<List<ObjectModel>>(
                future: objectsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: GuidePalette.accent));
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        t.get('errorLoadingObjects1') ?? 'Error al cargar objetos',
                        style: const TextStyle(color: GuidePalette.muted),
                      ),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox();
                  }
                  final objects = snapshot.data!;
                  return ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    scrollDirection: Axis.horizontal,
                    itemCount: objects.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final obj = objects[index].localized(
                        Localizations.localeOf(context).languageCode,
                      );
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(name: GuideRoutes.place),
                              builder: (_) => ObjectDetailScreen(object: obj),
                            ),
                          );
                        },
                        child: Container(
                          width: 160,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: GuidePalette.accent),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                                child: Image.asset(
                                  obj.imageUrl,
                                  width: double.infinity,
                                  height: 140,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(width: double.infinity, height: 140, color: Colors.grey[300], child: const Icon(Icons.error)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                child: Text(
                                  obj.name,
                                  style: AppFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: GuidePalette.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // Sección Recomendados
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 0, 12),
              child: Text(
                t.get('recommendedSection') ?? 'Recomendados',
                style: AppFonts.display(color: GuidePalette.ink, fontSize: 28),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<RecommendedModel>>(
              future: recommendedFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: GuidePalette.accent));
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      t.get('errorLoadingRecommended') ?? 'Error al cargar recomendados',
                      style: const TextStyle(color: GuidePalette.muted),
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox();
                }
                final recommended = snapshot.data!;
                return RecommendedWidget(recommendedList: recommended);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fotos de la casa. Se puede deslizar y avanza sola.
class _HouseCarousel extends StatefulWidget {
  final List<String> images;

  const _HouseCarousel({required this.images});

  @override
  State<_HouseCarousel> createState() => _HouseCarouselState();
}

class _HouseCarouselState extends State<_HouseCarousel> {
  final PageController _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _advance() {
    if (!mounted || widget.images.length < 2 || !_pages.hasClients) return;
    final next = (_index + 1) % widget.images.length;
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              return Image.asset(
                widget.images[index],
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: GuidePalette.surface,
                  child: Center(child: Icon(Icons.image_not_supported, color: GuidePalette.muted)),
                ),
              );
            },
          ),
          if (widget.images.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.images.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? GuidePalette.accent : GuidePalette.ink.withOpacity(0.45),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
