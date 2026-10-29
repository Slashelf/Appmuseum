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

  @override
  void initState() {
    super.initState();
    objectsFuture = loadObjects();
    recommendedFuture = loadRecommendedObjects();
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
                  Image.asset(
                    "assets/images/casa2.jpg",
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      t.get('homeBannerTitle') ?? 'Centro de Interpretación de la Cultura Funeraria',
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
                      t.get('homeBannerSubtitle') ?? 'La Casa Nacional de Moneda de Potosí guarda la sala de Melchor Pérez de Holguín, la Brocha de Oro, con los evangelistas de 1724 y el San Francisco de Asís de 1694.',
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
