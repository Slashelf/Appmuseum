import 'package:flutter/material.dart';
import '../core/navigation/place_route.dart';
import '../core/theme/app_theme.dart';
import '../models/recommended_model.dart';
import 'app_localizations.dart';

class MuseumDetailScreen extends StatelessWidget {
  final RecommendedModel museum;

  const MuseumDetailScreen({super.key, required this.museum});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final museum = this.museum.localized(
      Localizations.localeOf(context).languageCode,
    );
    return Scaffold(
      backgroundColor: GuidePalette.background,
      appBar: AppBar(
        title: Text(museum.title),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen del museo ocupa todo el ancho
            SizedBox(
              width: double.infinity,
              height: 250,
              child: Image.asset(
                museum.imageUrl,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),

            // Contenido con padding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título
                  Text(
                    museum.title,
                    style: AppFonts.display(
                      fontSize: 32,
                      color: GuidePalette.ink,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Ubicación debajo del título
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: GuidePalette.accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          museum.location,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: GuidePalette.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Descripción
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GuidePalette.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                      
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          museum.description,
                          style: const TextStyle(
                            fontSize: 16,
                            color: GuidePalette.muted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Horarios de atención
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GuidePalette.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                       
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.get('hoursTitle'),
                          style: AppFonts.display(fontSize: 26, color: GuidePalette.ink),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          museum.openingHours,
                          style: const TextStyle(
                            fontSize: 16,
                            color: GuidePalette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PlaceRouteButton(
                    latitude: museum.latitude,
                    longitude: museum.longitude,
                    address: museum.direccion ?? museum.location,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
