import 'package:flutter/material.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import '../models/object_model.dart';
import '../utils/load_objects.dart';
import 'object_detail_screen.dart';
import 'app_localizations.dart'; // <- Tus traducciones

class ExplorarTab extends StatefulWidget {
  const ExplorarTab({super.key});

  @override
  State<ExplorarTab> createState() => _ExplorarTabState();
}

class _ExplorarTabState extends State<ExplorarTab> {
  late Future<List<ObjectModel>> objectsFuture;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    objectsFuture = loadObjects();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context); // <- Traducciones

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('exploreMore') ?? 'Explorar más'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: GuidePalette.background,
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: t.get('search') ?? 'Buscar...',
                hintStyle: AppFonts.poppins(color: GuidePalette.muted),
                prefixIcon: const Icon(Icons.search, color: GuidePalette.accent),
                filled: true,
                fillColor: GuidePalette.fieldFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          // Lista de objetos
          Expanded(
            child: FutureBuilder<List<ObjectModel>>(
              future: objectsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final languageCode = Localizations.localeOf(context).languageCode;
                  final objects = snapshot.data!.where((obj) {
                    final localized = obj.localized(languageCode);
                    final haystack = '${obj.name} ${localized.name} ${localized.description}'
                        .toLowerCase();
                    return haystack.contains(searchQuery);
                  }).map((obj) => obj.localized(languageCode)).toList();

                  if (objects.isEmpty) {
                    return Center(
                      child: Text(
                        t.get('noResults') ?? 'No se encontraron resultados',
                        style: const TextStyle(color: GuidePalette.muted),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: objects.length,
                    itemBuilder: (context, index) {
                      final obj = objects[index];
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: GuidePalette.surface,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: GuidePalette.accent),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Imagen
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    obj.imageUrl,
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.error, color: Colors.red, size: 50),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Nombre
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    obj.name,
                                    style: AppFonts.display(
                                      fontSize: 26,
                                      color: GuidePalette.ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Descripción
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    obj.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: GuidePalette.muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      t.get('errorLoadingObjects') ?? 'Error al cargar objetos',
                      style: const TextStyle(color: GuidePalette.muted),
                    ),
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(color: GuidePalette.accent),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
