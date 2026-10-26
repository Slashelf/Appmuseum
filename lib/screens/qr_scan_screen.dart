import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import '../repositories/data_repository.dart';
import 'app_localizations.dart';
import 'object_detail_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController();
  bool scanned = false;
  String mensaje = '';

  // Animación de línea de escaneo
  late AnimationController _animationController;
  late Animation<double> _lineAnimation;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();

    _animationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _lineAnimation =
        Tween<double>(begin: 0, end: 1).animate(_animationController);
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      final result = await Permission.camera.request();
      if (!result.isGranted && mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.get('qrPermission')),
            backgroundColor: GuidePalette.surface,
          ),
        );
      }
    }
  }

  void _handleBarcode(String code) async {
    final t = AppLocalizations.of(context);
    scanned = true;
    setState(() {
      mensaje = t.get('qrProcessing');
    });

    final obj = await DataRepository.findByCode(code);

    if (obj != null) {
      controller.stop();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: GuideRoutes.place),
          builder: (_) => ObjectDetailScreen(object: obj),
        ),
      );
    } else {
      if (!mounted) return;
      final unknown = t.get('qrUnknown');
      setState(() {
        mensaje = unknown;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(unknown),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        scanned = false;
        mensaje = t.get('qrAim');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final caption = mensaje.isEmpty ? t.get('qrAim') : mensaje;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(t.get('qrTitle')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (scanned) return;
              final code = capture.barcodes.first.rawValue?.trim() ?? '';
              if (code.isNotEmpty) {
                _handleBarcode(code);
              }
            },
          ),

          // Overlay de escaneo
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: GuidePalette.accent, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Línea animada de escaneo
          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: AnimatedBuilder(
                animation: _lineAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _LinePainter(_lineAnimation.value),
                  );
                },
              ),
            ),
          ),

          // Mensaje en pantalla
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  caption,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    _animationController.dispose();
    super.dispose();
  }
}

// Pintor personalizado para la línea animada
class _LinePainter extends CustomPainter {
  final double position;

  _LinePainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GuidePalette.accent
      ..strokeWidth = 2;

    final y = size.height * position;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.position != position;
}
