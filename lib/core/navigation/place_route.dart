import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../screens/app_localizations.dart';
import '../theme/app_theme.dart';

/// Abre la navegación hacia un punto guardado, o la búsqueda de su dirección.
class PlaceRoute {
  static Uri? destination({
    double? latitude,
    double? longitude,
    String? address,
  }) {
    if (latitude != null && longitude != null && latitude != 0 && longitude != 0) {
      final point = '$latitude,$longitude';
      return Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': point,
        'travelmode': 'walking',
      });
    }
    final query = address?.trim() ?? '';
    if (query.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
  }

  static Future<void> open(
    BuildContext context, {
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final t = AppLocalizations.of(context);
    final uri = destination(latitude: latitude, longitude: longitude, address: address);
    if (uri == null) {
      _notice(context, t.get('routeUnavailable'));
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      _notice(context, t.get('routeFailed'));
    }
  }

  static void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class PlaceRouteButton extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String? address;

  const PlaceRouteButton({
    super.key,
    this.latitude,
    this.longitude,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => PlaceRoute.open(
          context,
          latitude: latitude,
          longitude: longitude,
          address: address,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: GuidePalette.accent,
          side: const BorderSide(color: GuidePalette.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        icon: const Icon(Icons.route, size: 18),
        label: Text(
          t.get('routeButton'),
          style: AppFonts.poppins(
            color: GuidePalette.accent,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
