import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Imagen de la guía. Si el archivo no está, muestra un recuadro vacío.
class GalleryImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  const GalleryImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (path.trim().isEmpty) return _missing(width, height);
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _missing(width, height),
    );
  }

  static Widget _missing(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: GuidePalette.fieldFill,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: GuidePalette.muted,
      ),
    );
  }
}

class GalleryThumb extends StatelessWidget {
  final String path;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  const GalleryThumb({
    super.key,
    required this.path,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GuidePalette.accent, width: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GalleryImage(
            path: path,
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Vista a pantalla completa. Se pasa de una imagen a otra deslizando.
class GalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const GalleryViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  static void open(BuildContext context, List<String> images, int index) {
    if (images.isEmpty) return;
    final start = index < 0 ? 0 : (index >= images.length ? images.length - 1 : index);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => GalleryViewer(images: images, initialIndex: start),
      ),
    );
  }

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GuidePalette.background,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                return Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: GalleryImage(
                      path: widget.images[index],
                      fit: BoxFit.contain,
                      width: MediaQuery.sizeOf(context).width,
                      height: MediaQuery.sizeOf(context).height,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: GuidePalette.accent),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Text(
                '${_index + 1} / ${widget.images.length}',
                textAlign: TextAlign.center,
                style: AppFonts.poppins(
                  color: GuidePalette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
