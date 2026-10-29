import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

class OnBoarding extends StatelessWidget {
  const OnBoarding({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final t = AppLocalizations.of(context); // <- Traducciones

    return Scaffold(
      backgroundColor: GuidePalette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/casa/fachada.jpg',
            fit: BoxFit.cover,
            width: screenWidth,
            height: screenHeight,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x660C0B09),
                  Color(0xF20C0B09),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/images/app_icon.png',
                    height: 56,
                    width: 56,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  Text(
                    t.get('mintApp'),
                    style: AppFonts.display(
                      fontSize: 42,
                      color: GuidePalette.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.get('onBoardingSubtitle'),
                    style: AppFonts.poppins(
                      fontSize: 15,
                      height: 1.4,
                      color: GuidePalette.muted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MainScreen(showTutorial: true),
                        ),
                      );
                    },
                    child: Container(
                      width: 210,
                      height: 48,
                      decoration: BoxDecoration(
                        color: GuidePalette.accent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t.get('start'),
                        style: AppFonts.poppins(
                          color: GuidePalette.onAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
