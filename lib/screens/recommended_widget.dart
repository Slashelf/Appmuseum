import 'package:flutter/material.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import '../models/recommended_model.dart';
import 'object_detail_rec.dart';

class RecommendedWidget extends StatelessWidget {
  final List<RecommendedModel> recommendedList;

  const RecommendedWidget({super.key, required this.recommendedList});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: recommendedList.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final museum = recommendedList[index].localized(
            Localizations.localeOf(context).languageCode,
          );
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: GuideRoutes.place),
                  builder: (_) => MuseumDetailScreen(museum: museum),
                ),
              );
            },
            child: Container(
              width: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: AssetImage(museum.imageUrl),
                  fit: BoxFit.cover,
                ),
                border: Border.all(color: GuidePalette.accent),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    museum.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
