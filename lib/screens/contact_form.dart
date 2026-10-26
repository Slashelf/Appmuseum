import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/content_repository.dart';
import 'app_localizations.dart';

class ContactForm extends StatefulWidget {
  const ContactForm({super.key});

  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> with TickerProviderStateMixin {
  late final AnimationController _iconController;
  late final Animation<double> _iconAnimation;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  int rating = 3; // ⭐ Valor inicial
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _iconAnimation = CurvedAnimation(parent: _iconController, curve: Curves.easeIn);
    _iconController.forward();
  }

  @override
  void dispose() {
    _iconController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Widget _gap() => const SizedBox(height: 16);

  Future<void> _submit() async {
    final t = AppLocalizations.of(context); 
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final comment = _commentController.text.trim();
    final repository = context.read<ContentRepository>();

    Future<void> showResult(String title, String message) {
      return showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: GuidePalette.surface,
          title: Text(
            title,
            style: const TextStyle(
              color: GuidePalette.ink,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: GuidePalette.muted,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _formKey.currentState!.reset();
                _nameController.clear();
                _emailController.clear();
                _commentController.clear();
                setState(() => rating = 3);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                decoration: BoxDecoration(
                  color: GuidePalette.accent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  t.get('ok'),
                  style: const TextStyle(
                    color: GuidePalette.onAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    try {
      if (Firebase.apps.isEmpty) {
        throw StateError('offline');
      }

      DocumentReference docRef =
          FirebaseFirestore.instance.collection("comentarios").doc(email);

      await docRef.set({
        "nombre": name,
        "email": email,
        "comentarios": FieldValue.arrayUnion([
          {"comentario": comment, "rating": rating, "fecha": Timestamp.now()}
        ]),
      }, SetOptions(merge: true));

      await showResult(t.get('Fsent'), t.get('FsentMessage'));
    } catch (e) {
      try {
        await repository.savePendingComment(
          PendingComment(
            name: name,
            email: email,
            comment: comment,
            rating: rating,
          ),
        );
        if (!mounted) return;
        await showResult(t.get('FsavedTitle'), t.get('savedLocally'));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.get('FerrorSend')} $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context); // <- Traducciones
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !_acknowledged,
          child: Container(
      width: double.infinity,
      height: size.height,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: const BoxDecoration(
        color: GuidePalette.background,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 80),
                  Text(
                    t.get('tituloContacto'),
                    textAlign: TextAlign.center,
                    style: AppFonts.display(fontSize: 32, color: GuidePalette.ink),
                  ),
                  _gap(),
                  Row(
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        icon: Icon(index < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 30),
                        onPressed: () => setState(() => rating = index + 1),
                      ),
                    ),
                  ),
                  _gap(),
                  TextFormField(
                    controller: _nameController,
                    validator: (value) => value == null || value.isEmpty ? t.get('FenterName') : null,
                    decoration: InputDecoration(
                      hintText: t.get('Fname'),
                      filled: true,
                      fillColor: GuidePalette.fieldFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.person, color: GuidePalette.accent),
                    ),
                    style: const TextStyle(color: GuidePalette.ink),
                  ),
                  _gap(),
                  TextFormField(
                    controller: _emailController,
                    validator: (value) {
                      if (value == null || value.isEmpty) return t.get('FenterEmail');
                      return RegExp(r".+@.+\..+").hasMatch(value) ? null : t.get('FinvalidEmail');
                    },
                    decoration: InputDecoration(
                      hintText: t.get('Femail'),
                      filled: true,
                      fillColor: GuidePalette.fieldFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.email_outlined, color: GuidePalette.accent),
                    ),
                    style: const TextStyle(color: GuidePalette.ink),
                  ),
                  _gap(),
                  TextFormField(
                    controller: _commentController,
                    maxLines: 5,
                    validator: (value) => value == null || value.isEmpty ? t.get('FwriteAComment') : null,
                    decoration: InputDecoration(
                      hintText: t.get('Fmessage'),
                      filled: true,
                      fillColor: GuidePalette.fieldFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    style: const TextStyle(color: GuidePalette.ink),
                  ),
                  const SizedBox(height: 25),
                  Center(
                    child: GestureDetector(
                      onTap: _submit,
                      child: Container(
                        width: 230,
                        height: 48,
                        decoration: BoxDecoration(
                          color: GuidePalette.accent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        alignment: Alignment.center,
                        child: Text(t.get('Fsubmit'), style: AppFonts.poppins(color: GuidePalette.onAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  FadeTransition(
                    opacity: _iconAnimation,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        FaIcon(FontAwesomeIcons.tiktok, color: GuidePalette.ink, size: 28),
                        FaIcon(FontAwesomeIcons.facebook, color: GuidePalette.ink, size: 28),
                        FaIcon(FontAwesomeIcons.instagram, color: GuidePalette.ink, size: 28),
                        FaIcon(FontAwesomeIcons.whatsapp, color: GuidePalette.ink, size: 28),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ),
          ),
        ),
        if (!_acknowledged)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: const Color(0xE60C0B09),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GuidePalette.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: GuidePalette.accent),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t.get('tituloContacto'),
                              textAlign: TextAlign.center,
                              style: AppFonts.display(
                                fontSize: 36,
                                color: GuidePalette.ink,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 24),
                            GestureDetector(
                              onTap: () => setState(() => _acknowledged = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                                decoration: BoxDecoration(
                                  color: GuidePalette.accent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  t.get('understood'),
                                  style: AppFonts.poppins(
                                    color: GuidePalette.onAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
