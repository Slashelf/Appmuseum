import 'package:app_guia_v1/core/navigation/place_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinates open a walking route and an address opens a search', () {
    final point = PlaceRoute.destination(latitude: -19.5885, longitude: -65.7583);
    expect(point, isNotNull);
    expect(point.toString(), contains('destination=-19.5885%2C-65.7583'));
    expect(point.toString(), contains('travelmode=walking'));

    final street = PlaceRoute.destination(address: 'Calle Tarija, Esq. Nogales N°47');
    expect(street.toString(), contains('/maps/search/'));
    expect(street.toString(), contains('Calle'));

    expect(PlaceRoute.destination(latitude: 0, longitude: 0), isNull);
    expect(PlaceRoute.destination(address: '   '), isNull);
  });

  test('stored recommendation coordinates are used as they are', () {
    final tambo = PlaceRoute.destination(latitude: -19.0333, longitude: -65.2633);
    expect(tambo.toString(), contains('-19.0333'));
    expect(tambo.toString(), contains('-65.2633'));
  });
}
