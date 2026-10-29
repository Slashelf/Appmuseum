import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// Lo que el personaje hace en el modo hablar.
enum GuideOrbMood { idle, listen, speak, error }

/// Nombres del ViewModel que mueven al personaje. No inventa un saludo.
class OrbPropertyNames {
  final String listen;
  final String speak;
  final String error;
  final String? greet;

  const OrbPropertyNames({
    required this.listen,
    required this.speak,
    required this.error,
    this.greet,
  });

  static const known = OrbPropertyNames(
    listen: 'typingBoolean',
    speak: 'jump',
    error: 'wrong',
  );

  static OrbPropertyNames detect(Iterable<ViewModelProperty> properties) {
    final listen = _pick(properties, _isListen) ?? known.listen;
    final speak = _pick(properties, _isSpeak) ?? known.speak;
    final error = _pick(properties, _isError) ?? known.error;
    return OrbPropertyNames(
      listen: listen,
      speak: speak,
      error: error,
      greet: _pick(properties, _isGreet),
    );
  }

  static String? _pick(
    Iterable<ViewModelProperty> properties,
    bool Function(String name) test,
  ) {
    String? fuzzy;
    for (final property in properties) {
      final name = property.name.toLowerCase();
      if (!test(name)) continue;
      if (name == 'typingboolean' || name == 'jump' || name == 'wrong' || name == 'hello' || name == 'greet') {
        return property.name;
      }
      fuzzy ??= property.name;
    }
    return fuzzy;
  }

  static bool _isListen(String name) => name.contains('typing');

  static bool _isSpeak(String name) => name == 'jump' || name.contains('jump');

  static bool _isError(String name) {
    return name == 'wrong' || name.contains('wrong') || name.contains('wince');
  }

  static bool _isGreet(String name) {
    const keys = ['hello', 'greet', 'wave', 'saludo', 'welcome'];
    for (final key in keys) {
      if (name.contains(key)) return true;
    }
    return false;
  }
}

/// Personaje del modo hablar. En reposo respira; el archivo ya trae ese estado.
class GuideOrb extends StatefulWidget {
  final GuideOrbMood mood;

  const GuideOrb({super.key, required this.mood});

  @override
  State<GuideOrb> createState() => _GuideOrbState();
}

class _GuideOrbState extends State<GuideOrb> {
  File? _file;
  RiveWidgetController? _controller;
  ViewModelInstanceBoolean? _listen;
  ViewModelInstanceTrigger? _speakTrigger;
  ViewModelInstanceBoolean? _speakBool;
  ViewModelInstanceTrigger? _errorTrigger;
  ViewModelInstanceBoolean? _errorBool;
  ViewModelInstanceTrigger? _greetTrigger;
  bool _greeted = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GuideOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _apply(widget.mood);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = await File.asset(
        'assets/rive/ai_orb_mascot.riv',
        riveFactory: Factory.rive,
      );
      if (!mounted || file == null) return;
      final controller = RiveWidgetController(file);
      final model = controller.dataBind(DataBind.auto());
      final names = OrbPropertyNames.detect(model.properties);
      _listen = model.boolean(names.listen);
      _speakTrigger = model.trigger(names.speak);
      _speakBool = _speakTrigger == null ? model.boolean(names.speak) : null;
      _errorTrigger = model.trigger(names.error);
      _errorBool = _errorTrigger == null ? model.boolean(names.error) : null;
      final greet = names.greet;
      if (greet != null) _greetTrigger = model.trigger(greet);
      _file = file;
      _controller = controller;
      _apply(widget.mood);
      if (!_greeted && _greetTrigger != null) {
        _greeted = true;
        _greetTrigger!.trigger();
      }
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _apply(GuideOrbMood mood) {
    _listen?.value = mood == GuideOrbMood.listen;
    if (mood == GuideOrbMood.speak) {
      _speakTrigger?.trigger();
      _speakBool?.value = true;
    } else {
      _speakBool?.value = false;
    }
    if (mood == GuideOrbMood.error) {
      _errorTrigger?.trigger();
      _errorBool?.value = true;
    } else {
      _errorBool?.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) return const SizedBox.expand();
    return RiveWidget(controller: controller, fit: Fit.contain);
  }
}
