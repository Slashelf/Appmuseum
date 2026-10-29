import 'package:app_guia_v1/core/navigation/place_navigation.dart';
import 'package:app_guia_v1/models/object_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new beacon replaces the open place screens', (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        homeContext = context;
        return const Text('home');
      }),
    ));

    Navigator.of(homeContext).push(MaterialPageRoute(
      settings: const RouteSettings(name: GuideRoutes.place),
      builder: (_) => const Text('place-a'),
    ));
    await tester.pumpAndSettle();
    Navigator.of(homeContext).push(MaterialPageRoute(
      settings: const RouteSettings(name: GuideRoutes.place),
      builder: (_) => const Text('place-b'),
    ));
    await tester.pumpAndSettle();

    openPlaceFromBeacon(
      homeContext,
      _place('place-c'),
      placeRoute: (place) => MaterialPageRoute(
        settings: const RouteSettings(name: GuideRoutes.place),
        builder: (_) => Text(place.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('place-c'), findsOneWidget);
    expect(find.text('place-a'), findsNothing);
    expect(find.text('place-b'), findsNothing);

    Navigator.of(homeContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a beacon does not cover the chat', (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        homeContext = context;
        return const Text('home');
      }),
    ));
    Navigator.of(homeContext).push(MaterialPageRoute(
      settings: const RouteSettings(name: GuideRoutes.chat),
      builder: (_) => const Text('chat'),
    ));
    await tester.pumpAndSettle();

    openPlaceFromBeacon(
      homeContext,
      _place('place-c'),
      placeRoute: (place) => MaterialPageRoute(
        settings: const RouteSettings(name: GuideRoutes.place),
        builder: (_) => Text(place.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('chat'), findsOneWidget);
    expect(find.text('place-c'), findsNothing);
  });

  testWidgets('a beacon does not close talk mode', (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        homeContext = context;
        return const Text('home');
      }),
    ));
    Navigator.of(homeContext).push(MaterialPageRoute(
      settings: const RouteSettings(name: GuideRoutes.talk),
      builder: (_) => const Text('talk'),
    ));
    await tester.pumpAndSettle();

    openPlaceFromBeacon(
      homeContext,
      _place('place-c'),
      placeRoute: (place) => MaterialPageRoute(
        settings: const RouteSettings(name: GuideRoutes.place),
        builder: (_) => Text(place.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('talk'), findsOneWidget);
    expect(find.text('place-c'), findsNothing);
  });
}

ObjectModel _place(String id) {
  return ObjectModel(
    id: id,
    name: id,
    name2: id,
    description: id,
    cryptDescription: '',
    imageUrl: '',
    imageUrl2: '',
  );
}
