/// Preguntas que el chat sabe reconocer y la frase corta con la que las dice.
///
/// El dato sale de la ficha. Aquí solo se elige cuál dato y cómo presentarlo.
enum AnswerFocus {
  story,
  crypt,
  hours,
  address,
  fee,
  style,
  year,
  name,
  here,
  route,
  noroute,
  aside,
}

class ChatFaq {
  static const _stopwords = {
    'que', 'qué', 'del', 'las', 'los', 'una', 'uno', 'con', 'por', 'para',
    'como', 'cómo', 'donde', 'dónde', 'esta', 'este', 'eso', 'esa', 'the',
    'and', 'for', 'with', 'what', 'where', 'when', 'und', 'der', 'die', 'das',
    'ein', 'eine', 'ist', 'sind', 'von', 'mit', 'auf', 'wie', 'wo',
  };

  static const _hereWords = {
    'aqui', 'aca', 'ahi', 'here', 'hier', 'estoy', 'viendo', 'seeing',
  };

  static const _routeWords = {
    'llego', 'llegar', 'llega', 'llegamos', 'ruta', 'camino', 'directions',
    'route', 'weg', 'anfahrt', 'gelangen', 'hinfinden',
  };

  static const _yearWords = {
    'ano', 'anio', 'year', 'years', 'jahr', 'jahre', 'fecha', 'fechas',
    'date', 'dates', 'datum', 'fundado', 'fundada', 'founded', 'gegrundet',
    'gegruendet',
  };

  static const _hoursWords = {
    'horario', 'horarios', 'hours', 'hour', 'opening', 'offen',
    'offnungszeiten', 'oeffnungszeiten', 'abre', 'abren', 'cierra', 'cierran',
    'hora', 'horas', 'uhrzeit', 'geoffnet',
  };

  static const _addressWords = {
    'direccion', 'address', 'adresse', 'calle', 'street', 'ubicacion',
    'ubicado', 'queda', 'location', 'standort', 'donde',
  };

  static const _feeWords = {
    'precio', 'entrada', 'tarifa', 'fee', 'price', 'cost', 'preis',
    'eintritt', 'kosten', 'cuesta', 'cuestan',
  };

  static const _styleWords = {
    'estilo', 'style', 'stil', 'arquitectura', 'architectural',
  };

  static const _cryptWords = {
    'cripta', 'criptas', 'crypt', 'crypts', 'krypta', 'krypte', 'krypten',
  };

  static const _nameWords = {
    'nombre', 'name', 'llama', 'llamado', 'llamada', 'called', 'heisst',
    'namens',
  };

  static const _placeKind = {
    'iglesia', 'iglesias', 'church', 'churches', 'kirche', 'kirchen',
    'templo', 'templos', 'temple', 'temples', 'tempel', 'convento',
    'conventos', 'convent', 'kloster', 'basilica', 'capilla',
  };

  static const _detailWords = {
    'detalle', 'detalles', 'todo', 'toda', 'completa', 'completo', 'mas',
    'more', 'detail', 'details', 'alles', 'mehr', 'weiter', 'amplia',
    'ampliar', 'historia', 'history', 'geschichte', 'hay',
  };

  static const _social = {
    'hola', 'hello', 'hi', 'hey', 'hallo', 'buenas', 'buenos', 'buen',
    'dias', 'tardes', 'noches', 'guten', 'tag', 'moin', 'morning',
    'gracias', 'thanks', 'thank', 'danke', 'adios', 'chao', 'bye',
    'tschuss', 'tschau', 'hasta', 'luego', 'estas', 'esta', 'gehts',
    'geht', 'how', 'are', 'you', 'tal', 'ayuda', 'help', 'hilfe',
    'puedes', 'hacer', 'puedo', 'ok', 'okay', 'vale', 'bien', 'good',
    'ja', 'yes', 'si', 'claro', 'genial', 'perfecto',
  };

  static const _synonyms = {
    'iglesia': ['templo', 'convento', 'cripta'],
    'iglesias': ['templos', 'conventos', 'criptas'],
    'church': ['temple', 'convent', 'crypt'],
    'kirche': ['tempel', 'kloster', 'krypta'],
    'templo': ['iglesia', 'convento'],
    'temple': ['church', 'convent'],
    'convento': ['templo', 'iglesia'],
    'convent': ['church', 'temple'],
  };

  static const _filler = {
    'cual', 'cuales', 'which', 'welche', 'welcher', 'welches', 'sobre',
    'about', 'esto', 'esos', 'esas', 'these', 'those', 'hay', 'tiene',
    'tienen', 'incluye', 'incluyen', 'recorrido', 'guia', 'guide',
    'fuehrung', 'fuhrung', 'lugar', 'place', 'sitio', 'ort', 'dime',
    'cuentame', 'cuenta', 'tell', 'saber', 'know', 'wissen', 'puedes',
    'puede', 'puedo', 'can', 'could', 'kannst', 'bitte', 'please', 'favor',
    'algo', 'something', 'etwas', 'informacion', 'info', 'datos', 'potosi',
    'memoriam', 'tour', 'visita', 'visit', 'besuch', 'historia', 'history',
    'geschichte', 'patrimonio', 'erzahle', 'erzahlen', 'recomiendas',
    'recomiendo', 'recomienda', 'recommend', 'recommends', 'recommended',
    'empfiehlst', 'empfehlst', 'empfehlung', 'empfiehlt',
  };

  static const _smallTalk = {
    'tu', 'te', 'ti', 'usted', 'ustedes', 'yo', 'me', 'mi', 'mis', 'you',
    'your', 'du', 'dir', 'dich', 'dein', 'deine', 'ihnen', 'ihr', 'sie',
    'muy', 'mucho', 'muchas', 'very', 'hoy', 'today', 'heute', 'amigo',
    'amiga', 'friend', 'mal', 'fine', 'doing', 'going', 'llamas', 'llamo',
    'quien', 'eres', 'soy', 'who', 'heisst', 'heisse', 'heissen', 'name',
    'nombre', 'es', 'is', 'ist', 'bin', 'ich', 'am', 'im', 'mein', 'meine',
    'se', 'it',
  };

  static AnswerFocus focusFor(String question) {
    final words = _words(question);
    if (asksRoute(question)) return AnswerFocus.route;
    if (_hits(words, _yearWords)) return AnswerFocus.year;
    if (_hits(words, _hoursWords)) return AnswerFocus.hours;
    if (_hits(words, _feeWords)) return AnswerFocus.fee;
    if (_hits(words, _styleWords)) return AnswerFocus.style;
    if (_hits(words, _cryptWords)) return AnswerFocus.crypt;
    if (_hits(words, _addressWords)) return AnswerFocus.address;
    if (asksHere(question)) return AnswerFocus.here;
    if (_hits(words, _nameWords)) return AnswerFocus.name;
    return AnswerFocus.story;
  }

  static bool asksRoute(String question) => _hits(_words(question), _routeWords);

  static bool asksHere(String question) {
    if (asksRoute(question)) return false;
    final words = _words(question);
    if (_hits(words, _hereWords)) return true;
    final points = words.contains('este') ||
        words.contains('this') ||
        words.contains('dieser') ||
        words.contains('dieses') ||
        words.contains('diesem');
    if (!points) return false;
    const placePoint = {'lugar', 'place', 'sitio', 'ort', 'es', 'ist', 'hay', 'was'};
    return _hits(words, placePoint);
  }

  static bool asksSpecific(String question) {
    final words = _words(question);
    return _hits(words, _yearWords) ||
        _hits(words, _hoursWords) ||
        _hits(words, _feeWords) ||
        _hits(words, _styleWords) ||
        _hits(words, _addressWords);
  }

  /// La pregunta pide un relato, no solo el nombre o un dato suelto.
  static bool wantsDetail(String question) {
    final words = _words(question);
    if (words.any(_detailWords.contains)) return true;
    final how = words.contains('como') || words.contains('how') || words.contains('wie');
    final be = words.contains('son') ||
        words.contains('es') ||
        words.contains('are') ||
        words.contains('sind') ||
        words.contains('sehen');
    return how && be;
  }

  static String? factFor({
    required AnswerFocus focus,
    required String name,
    required String description,
    required String crypt,
    required String notes,
    required String hours,
    required String address,
    required String location,
    required String fee,
    required String style,
    required List<String> questionTokens,
    bool detailed = false,
  }) {
    switch (focus) {
      case AnswerFocus.hours:
        return _orNull(hours);
      case AnswerFocus.address:
      case AnswerFocus.route:
        return _orNull(address.trim().isNotEmpty ? address : location);
      case AnswerFocus.fee:
        return _orNull(fee);
      case AnswerFocus.style:
        return _orNull(style);
      case AnswerFocus.name:
        return _orNull(name);
      case AnswerFocus.year:
        return _yearText(_narrative(description, crypt, notes));
      case AnswerFocus.crypt:
        final burial = description.trim();
        final essay = crypt.trim();
        final source = _mentionsCrypt(burial)
            ? burial
            : _mentionsCrypt(essay)
                ? essay
                : '';
        if (source.isEmpty) return null;
        return _limit(source, questionTokens, detailed: true);
      case AnswerFocus.here:
      case AnswerFocus.noroute:
      case AnswerFocus.aside:
        final about = _narrative(description, crypt, notes);
        if (about.isEmpty) return _orNull(name);
        return _limit(about, questionTokens, detailed: focus == AnswerFocus.here);
      case AnswerFocus.story:
        final asksChurch = questionTokens.any(_placeKind.contains) &&
            !questionTokens.any(_cryptWords.contains);
        final church = crypt.trim();
        final story = asksChurch && church.isNotEmpty
            ? church
            : _narrative(description, crypt, notes);
        if (story.isEmpty) return null;
        final extra = contentTokens(questionTokens, name);
        final broad = extra.isEmpty || extra.every(_placeKind.contains) || detailed;
        if (broad) return _limit(story, questionTokens, detailed: detailed);
        final matched = _matchingSentences(story, extra);
        if (matched == null) return null;
        return _limit(matched, questionTokens, detailed: detailed);
    }
  }

  /// Saludo, estado de ánimo, nombre del asistente, gracias o adiós.
  /// Null si la frase pide un dato del lugar.
  static String? socialReply(String question, String languageCode) {
    final words = _words(question);
    if (words.isEmpty || _hasTopic(words)) return null;
    final kind = _socialIntent(words);
    if (kind == null) return null;
    final allowed = {..._social, ..._stopwords, ..._smallTalk};
    if (words.any((word) => word.length > 1 && !allowed.contains(word))) {
      return null;
    }
    final lines = _socialLines[_language(languageCode)]![kind]!;
    return lines[question.length % lines.length];
  }

  static String unknownPlace(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I do not recognize the place yet. Come closer or tell me the name.';
      case 'de':
        return 'Den Ort erkenne ich noch nicht. Kommen Sie näher oder nennen Sie mir den Namen.';
      default:
        return 'Aún no reconozco el lugar. Acércate o dime el nombre.';
    }
  }

  static String unsure(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I am not sure about that, but I can tell you what I know about this place.';
      case 'de':
        return 'Das weiß ich nicht sicher, aber ich kann erzählen, was ich über diesen Ort weiß.';
      default:
        return 'No tengo ese dato con seguridad, pero puedo contarte lo que sé de este lugar.';
    }
  }

  static String noRoute(String languageCode, String? about) {
    final place = about?.trim() ?? '';
    switch (_language(languageCode)) {
      case 'en':
        if (place.isEmpty) {
          return 'I do not have a street-by-street route. Tell me the place and I will share the address if I have it.';
        }
        return 'I do not have a street-by-street route. What I can tell you is this: $place';
      case 'de':
        if (place.isEmpty) {
          return 'Einen Weg Straße für Straße habe ich nicht. Nennen Sie mir den Ort, dann sage ich die Adresse, wenn sie gespeichert ist.';
        }
        return 'Einen Weg Straße für Straße habe ich nicht. Das kann ich Ihnen sagen: $place';
      default:
        if (place.isEmpty) {
          return 'No tengo el camino calle por calle. Dime el lugar y te digo la dirección, si está guardada.';
        }
        return 'No tengo el camino calle por calle. De este lugar sí puedo contarte esto: $place';
    }
  }

  static String leadSentence(String text) {
    final sentences = _sentences(text);
    if (sentences.isEmpty) return text.trim();
    return sentences.first;
  }

  static String clarify(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'Tell me a bit more. Which place do you mean?';
      case 'de':
        return 'Erzählen Sie mir etwas mehr. Welchen Ort meinen Sie?';
      default:
        return 'Cuéntame un poco más. ¿De qué lugar hablas?';
    }
  }

  static String choice(String names, String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I can tell you about $names. Which one do you want?';
      case 'de':
        return 'Ich kann Ihnen von $names erzählen. Welcher interessiert Sie?';
      default:
        return 'Puedo contarte de $names. ¿De cuál quieres saber?';
    }
  }

  static bool hasContent(String question) {
    final words = _words(question);
    return words.any(
      (word) => !_social.contains(word) && !_stopwords.contains(word) && word.length > 1,
    );
  }

  static List<String> expandTokens(List<String> questionTokens) {
    final expanded = <String>[...questionTokens];
    for (final token in questionTokens) {
      expanded.addAll(_synonyms[token] ?? const []);
    }
    return expanded;
  }

  static List<String> contentTokens(List<String> questionTokens, String name) {
    final nameTokens = tokens(name);
    return questionTokens.where((token) {
      if (_filler.contains(token)) return false;
      return !nameTokens.any((nameToken) => _near(token, nameToken));
    }).toList();
  }

  static String phrase({
    required AnswerFocus focus,
    required String fact,
    required String title,
    required String languageCode,
    required String question,
  }) {
    final language = _language(languageCode);
    switch (focus) {
      case AnswerFocus.hours:
        return _slot(language, 'hours', fact);
      case AnswerFocus.address:
        return _slot(language, 'address', fact);
      case AnswerFocus.fee:
        return _slot(language, 'fee', fact);
      case AnswerFocus.style:
        return _slot(language, 'style', fact);
      case AnswerFocus.name:
        return _slot(language, 'name', fact);
      case AnswerFocus.year:
        return _voiceYear(fact, language);
      case AnswerFocus.route:
        return _routeLine(language, fact);
      case AnswerFocus.noroute:
        return noRoute(language, _voiceProse(fact, language, ''));
      case AnswerFocus.story:
      case AnswerFocus.crypt:
      case AnswerFocus.here:
      case AnswerFocus.aside:
        return _voiceProse(fact, language, title);
    }
  }

  static String _routeLine(String language, String fact) {
    final value = fact.trim();
    switch (language) {
      case 'en':
        return 'You will find it at $value. I do not have a street-by-street route.';
      case 'de':
        return 'Sie finden es hier: $value. Einen Weg Straße für Straße habe ich nicht.';
      default:
        return 'Lo encuentras en $value. No tengo el camino calle por calle.';
    }
  }

  static String _language(String languageCode) {
    return languageCode == 'en' || languageCode == 'de' ? languageCode : 'es';
  }

  static bool _hasTopic(List<String> words) {
    const extra = {
      'historia', 'history', 'geschichte', 'viendo', 'seeing', 'lugar',
      'place', 'sitio', 'museo', 'museos', 'museum', 'museen', 'maquina',
      'laminado', 'moneda', 'ceca',
    };
    return _hits(words, _cryptWords) ||
        _hits(words, _hoursWords) ||
        _hits(words, _addressWords) ||
        _hits(words, _yearWords) ||
        _hits(words, _feeWords) ||
        _hits(words, _styleWords) ||
        _hits(words, _placeKind) ||
        _hits(words, _routeWords) ||
        _hits(words, extra);
  }

  static String? _socialIntent(List<String> words) {
    const thanks = {'gracias', 'thanks', 'thank', 'danke'};
    const bye = {'adios', 'chao', 'bye', 'tschuss', 'tschau', 'hasta', 'luego'};
    const help = {'ayuda', 'help', 'hilfe', 'puedes', 'hacer', 'puedo'};
    const greetings = {
      'hola', 'hello', 'hi', 'hey', 'hallo', 'buenas', 'buenos', 'buen',
      'dias', 'tardes', 'noches', 'guten', 'tag', 'moin', 'morning',
    };
    const ack = {
      'ok', 'okay', 'vale', 'bien', 'good', 'ja', 'yes', 'si', 'claro',
      'genial', 'perfecto',
    };
    const botName = {
      'llamas', 'llamo', 'quien', 'eres', 'who', 'heisst', 'heisse', 'heissen',
    };
    if (words.any(thanks.contains)) return 'thanks';
    if (words.any(bye.contains)) return 'bye';
    final asksBot = words.any(botName.contains) ||
        (words.contains('name') &&
            (words.contains('your') || words.contains('tu') || words.contains('dein'))) ||
        (words.contains('nombre') && (words.contains('tu') || words.contains('te')));
    if (asksBot) return 'name';
    final mood = words.contains('estas') ||
        words.contains('gehts') ||
        (words.contains('how') && words.contains('you')) ||
        (words.contains('wie') && (words.contains('geht') || words.contains('gehts'))) ||
        (words.contains('que') && words.contains('tal'));
    if (mood) return 'mood';
    if (words.any(help.contains)) return 'help';
    if (words.every(ack.contains)) return 'ack';
    if (words.any(greetings.contains)) return 'hi';
    return null;
  }

  static const _socialLines = {
    'es': {
      'hi': [
        'Hola. ¿Qué tal?',
        'Hola, me alegra leerte.',
        'Buenas. ¿Cómo estás?',
      ],
      'thanks': ['De nada.', 'Con gusto.', 'No hay de qué.'],
      'bye': ['Hasta luego.', 'Cuídate.', 'Nos vemos.'],
      'mood': ['Bien, gracias. ¿Y tú?', 'Todo bien por aquí. ¿Tú qué tal?'],
      'help': [
        'Podemos conversar. Si preguntas por un lugar, te cuento solo lo que sé de ese sitio.',
      ],
      'ack': ['Te escucho.', 'Dime.', 'Sigo aquí.'],
      'name': [
        'Soy la guía de Potosí Memoriam.',
        'Me puedes decir guía. Acompaño la visita en Potosí Memoriam.',
      ],
    },
    'en': {
      'hi': ['Hi. How are you?', 'Hello, good to hear from you.', 'Hey. How is it going?'],
      'thanks': ['You are welcome.', 'Glad to help.', 'Anytime.'],
      'bye': ['See you.', 'Take care.', 'Bye for now.'],
      'mood': ['I am well, thanks. And you?', 'Doing fine. How about you?'],
      'help': [
        'We can just talk. If you ask about a place, I will tell you only what I know about it.',
      ],
      'ack': ['I am listening.', 'Go ahead.', 'I am here.'],
      'name': [
        'I am the Potosí Memoriam guide.',
        'You can call me the guide. I walk with you through Potosí Memoriam.',
      ],
    },
    'de': {
      'hi': ['Hallo. Wie geht es Ihnen?', 'Hallo, schön von Ihnen zu hören.', 'Guten Tag. Wie geht es Ihnen?'],
      'thanks': ['Gern geschehen.', 'Sehr gern.', 'Nichts zu danken.'],
      'bye': ['Bis später.', 'Passen Sie auf sich auf.', 'Auf Wiedersehen.'],
      'mood': ['Gut, danke. Und Ihnen?', 'Mir geht es gut. Und Ihnen?'],
      'help': [
        'Wir können uns unterhalten. Wenn Sie nach einem Ort fragen, erzähle ich nur, was ich darüber weiß.',
      ],
      'ack': ['Ich höre.', 'Nur zu.', 'Ich bin da.'],
      'name': [
        'Ich bin die Führung von Potosí Memoriam.',
        'Sie können mich Führung nennen. Ich begleite den Besuch in Potosí Memoriam.',
      ],
    },
  };

  static String _slot(String language, String kind, String fact) {
    final value = fact.trim();
    switch (language) {
      case 'en':
        switch (kind) {
          case 'hours':
            return 'You can go at this time: $value.';
          case 'address':
            return 'You will find it at $value.';
          case 'fee':
            return 'Getting in costs $value.';
          case 'style':
            return 'Its style is $value.';
          default:
            return 'It is called $value.';
        }
      case 'de':
        switch (kind) {
          case 'hours':
            return 'Sie können zu dieser Zeit hingehen: $value.';
          case 'address':
            return 'Sie finden es hier: $value.';
          case 'fee':
            return 'Der Eintritt kostet $value.';
          case 'style':
            return 'Der Stil ist $value.';
          default:
            return 'Es heißt $value.';
        }
      default:
        switch (kind) {
          case 'hours':
            return 'Puedes ir en este horario: $value.';
          case 'address':
            return 'Lo encuentras en $value.';
          case 'fee':
            return 'Entrar cuesta $value.';
          case 'style':
            return 'Su estilo es $value.';
          default:
            return 'Se llama $value.';
        }
    }
  }

  static String _voiceYear(String fact, String language) {
    final years = RegExp(r'(?<![0-9])(1[5-9][0-9]{2}|20[0-9]{2})(?![0-9])')
        .allMatches(fact)
        .map((match) => match.group(1)!)
        .toList();
    if (years.isEmpty) return _voiceProse(fact, language, '');
    final joined = years.join(language == 'en' ? ' and ' : language == 'de' ? ' und ' : ' y ');
    switch (language) {
      case 'en':
        return 'The year I can mention is $joined.';
      case 'de':
        return 'Das Jahr, das ich nennen kann, ist $joined.';
      default:
        return 'El año del que puedo hablarte es $joined.';
    }
  }

  static String _voiceProse(String fact, String language, String title) {
    final sentences = _sentences(fact).take(2).map((sentence) {
      return _rewordSentence(sentence, language);
    }).where((sentence) => sentence.isNotEmpty).toList();
    if (sentences.isEmpty) return fact.trim();
    final spoken = sentences.join(' ');
    if (title.trim().isEmpty || spoken.toLowerCase().contains(title.trim().toLowerCase())) {
      return spoken;
    }
    switch (language) {
      case 'en':
        return 'About $title: $spoken';
      case 'de':
        return 'Zu $title: $spoken';
      default:
        return 'Sobre $title: $spoken';
    }
  }

  static String _rewordSentence(String sentence, String language) {
    var text = sentence.trim();
    if (text.endsWith('.')) text = text.substring(0, text.length - 1).trim();
    if (language == 'en') return _rewordEn(text);
    if (language == 'de') return _rewordDe(text);
    return _rewordEs(text);
  }

  static String _rewordEs(String text) {
    final crypts = RegExp(
      r'^Las criptas del (.+?) en Potos[ií] se encuentran en (.+?) y fueron utilizadas durante la época colonial como lugares de entierro para (.+)$',
      caseSensitive: false,
    );
    final cryptMatch = crypts.firstMatch(text);
    if (cryptMatch != null) {
      return 'En el ${cryptMatch.group(1)}, las criptas están en ${cryptMatch.group(2)}. '
          'En la colonia servían para enterrar a ${cryptMatch.group(3)}.';
    }
    final keeps = RegExp(r'^(.+?) guardan (.+)$', caseSensitive: false);
    final keepMatch = keeps.firstMatch(text);
    if (keepMatch != null) {
      return 'Ahí se conserva ${keepMatch.group(2)}.';
    }
    final founded = RegExp(r'^(.+?) se fund[oó] en (\d{4})$', caseSensitive: false);
    final foundedMatch = founded.firstMatch(text);
    if (foundedMatch != null) {
      return '${foundedMatch.group(1)} tiene como año ${foundedMatch.group(2)}.';
    }
    if (!_hasVerb(normalize(text))) {
      final lower = text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
      return 'Se trata de $lower.';
    }
    final softened = text
        .replaceAll('se encuentran', 'están')
        .replaceAll('fueron utilizadas', 'se usaron')
        .replaceAll('fueron utilizados', 'se usaron')
        .replaceAll('comenzó a funcionar', 'empezó a funcionar')
        .replaceAll('se construyó', 'se levantó');
    if (softened != text) {
      return softened.endsWith('.') ? softened : '$softened.';
    }
    return '$text.';
  }

  static String _rewordEn(String text) {
    final keeps = RegExp(r'^The (.+?) keeps (.+)$', caseSensitive: false);
    final keepMatch = keeps.firstMatch(text);
    if (keepMatch != null) {
      return 'What you find in the ${keepMatch.group(1)} is ${keepMatch.group(2)}.';
    }
    if (!_hasVerb(normalize(text))) {
      final lower = text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
      return 'It is $lower.';
    }
    return '$text.';
  }

  static String _rewordDe(String text) {
    if (!_hasVerb(normalize(text))) {
      return 'Es geht um $text.';
    }
    return '$text.';
  }

  static bool _hasVerb(String normalized) {
    const verbs = {
      'es', 'son', 'esta', 'estan', 'fue', 'fueron', 'guarda', 'guardan',
      'tiene', 'tienen', 'comenzo', 'construyo', 'se', 'keeps', 'keep',
      'was', 'were', 'holds', 'ist', 'sind', 'war', 'wurde', 'liegen',
      'liegt', 'befindet',
    };
    return _words(normalized).any(verbs.contains);
  }

  static String _limit(String text, List<String> questionTokens, {bool detailed = false}) {
    final sentences = _sentences(text);
    if (sentences.isEmpty) return text.trim();
    final max = detailed || questionTokens.any(_detailWords.contains) ? 2 : 1;
    return sentences.take(max).join(' ');
  }

  static bool _mentionsCrypt(String text) => _hits(_words(text), _cryptWords);

  static List<String> tokens(String value) {
    return _words(value)
        .where((token) => token.length >= 4 && !_stopwords.contains(token))
        .toList();
  }

  static int overlap(List<String> tokens, String field) {
    if (tokens.isEmpty || field.trim().isEmpty) return 0;
    final fieldTokens = _words(field).where((token) => token.length >= 4).toList();
    var score = 0;
    for (final token in tokens) {
      if (fieldTokens.any((fieldToken) => _near(token, fieldToken))) score += 1;
    }
    return score;
  }

  /// Vacío, spam o un tema fuera de la visita. El filtro no redacta la respuesta.
  static bool isSpam(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return false;
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= 8 && RegExp(r'^(.)\1+$').hasMatch(compact)) return true;
    return RegExp(r'^(https?://|www\.)\S+$', caseSensitive: false).hasMatch(trimmed);
  }

  static bool isOffTopic(String question) {
    final words = _words(question);
    if (words.isEmpty || !_hits(words, _offTopicWords)) return false;
    return !_hits(words, _heritageWords);
  }

  static String offTopicReply(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I cannot help with that. Ask me about the places, their history, and what you can see on the visit.';
      case 'de':
        return 'Dabei kann ich nicht helfen. Fragen Sie mich nach den Orten, ihrer Geschichte und dem, was Sie bei dem Besuch sehen.';
      default:
        return 'De eso no puedo hablar. Pregúntame por los lugares, su historia y lo que puedes ver en la visita.';
    }
  }

  static String cannotDraft(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I cannot draft an answer right now. Try again when there is a connection.';
      case 'de':
        return 'Ich kann die Antwort gerade nicht formulieren. Versuchen Sie es erneut, wenn eine Verbindung besteht.';
      default:
        return 'Ahora no puedo redactar la respuesta. Inténtalo de nuevo cuando haya conexión.';
    }
  }

  static String missingKey(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'The DeepSeek key is missing. Paste it to get an answer.';
      case 'de':
        return 'Der DeepSeek-Schlüssel fehlt. Fügen Sie ihn ein, um eine Antwort zu erhalten.';
      default:
        return 'Falta la clave de DeepSeek. Pégala para poder responder.';
    }
  }

  static String couldNotConnect(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'I could not connect. Try again.';
      case 'de':
        return 'Ich konnte keine Verbindung herstellen. Versuchen Sie es erneut.';
      default:
        return 'No pude conectar, intenta de nuevo.';
    }
  }

  static String noCredit(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'DeepSeek has no credit. Recharge the account to continue.';
      case 'de':
        return 'DeepSeek hat kein Guthaben. Laden Sie das Konto auf, um fortzufahren.';
      default:
        return 'DeepSeek no tiene crédito. Recarga la cuenta para seguir.';
    }
  }

  static const _offTopicWords = {
    'dolor', 'cabeza', 'enfermedad', 'medico', 'medicina', 'medicamento',
    'sintoma', 'sintomas', 'hospital', 'pastilla', 'doctor', 'fiebre',
    'cancer', 'diagnostico', 'tratamiento', 'headache', 'sick', 'medicine',
    'symptom', 'symptoms', 'arzt', 'krank', 'medizin', 'schmerz',
    'abogado', 'demanda', 'juicio', 'lawyer', 'lawsuit', 'anwalt', 'gesetz',
    'contrato', 'eleccion', 'elecciones', 'voto', 'votar', 'candidato',
    'presidente', 'election', 'elections', 'president', 'wahl', 'praesident',
    'politica', 'politico', 'politics',
  };

  static const _heritageWords = {
    'potosi', 'iglesia', 'iglesias', 'convento', 'conventos', 'cripta',
    'criptas', 'templo', 'templos', 'museo', 'museos', 'historia',
    'historico', 'cultura', 'turismo', 'colonial', 'visita', 'church',
    'convent', 'crypt', 'crypts', 'museum', 'history', 'kirche', 'kloster',
    'krypta', 'geschichte', 'francisco', 'merced', 'moneda', 'laminado',
  };

  static bool _near(String token, String fieldToken) {
    if (token.length <= 2 || fieldToken.length <= 2) return false;
    if (fieldToken == token) return true;
    if (token.length >= 4 &&
        (fieldToken.startsWith(token) || token.startsWith(fieldToken))) {
      return true;
    }
    final allowance = token.length >= 8 ? 2 : token.length >= 5 ? 1 : 0;
    if (allowance == 0) return false;
    if ((token.length - fieldToken.length).abs() > allowance) return false;
    return _edits(token, fieldToken) <= allowance;
  }

  static int _edits(String a, String b) {
    final rows = b.length + 1;
    var previous = List<int>.generate(rows, (index) => index);
    var current = List<int>.filled(rows, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      var best = current[0];
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        final value = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((left, right) => left < right ? left : right);
        current[j + 1] = value;
        if (value < best) best = value;
      }
      if (best > 2) return best;
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }

  static String normalize(String value) {
    const pairs = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
      'ß': 'ss',
    };
    final buffer = StringBuffer();
    for (final char in value.toLowerCase().split('')) {
      buffer.write(pairs[char] ?? char);
    }
    return buffer.toString();
  }

  static List<String> _words(String value) {
    return normalize(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  static bool _hits(List<String> words, Set<String> vocab) {
    return words.any(vocab.contains);
  }

  static String _narrative(String description, String crypt, String notes) {
    if (description.trim().isNotEmpty) return description.trim();
    if (crypt.trim().isNotEmpty) return crypt.trim();
    return notes.trim();
  }

  static String? _orNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _yearText(String text) {
    if (text.isEmpty) return null;
    final years = RegExp(r'(?<![0-9])(1[5-9][0-9]{2}|20[0-9]{2})(?![0-9])');
    final hits = _sentences(text).where(years.hasMatch).toList();
    if (hits.isEmpty) return null;
    return hits.join(' ');
  }

  static String? _matchingSentences(String text, List<String> questionTokens) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || questionTokens.isEmpty) return null;
    final hits = _sentences(trimmed)
        .where((sentence) => overlap(questionTokens, sentence) > 0)
        .toList();
    if (hits.isEmpty) return null;
    return hits.join(' ');
  }

  static List<String> _sentences(String text) {
    final parts = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? [text.trim()] : parts;
  }
}


