# app_guia_v1

Guía del Centro de Interpretación de la Cultura Funeraria de Potosí. Funciona sin Internet.

## Datos locales

En el primer arranque, `JsonSeeder` copia `assets/data/objects.json`, `recommended.json`, `view.json` y `object_carousel.json` a SQLite (`guia.db`). Los identificadores, las rutas de imagen y el español original se conservan. Inglés y alemán están en `assets/data/i18n/content_i18n.json`. Si falta una frase, se muestra el español.

`ContentRepository` es el contrato de lectura. Hoy lo implementa `LocalContentRepository`. `RemoteContentRepository` queda preparado para una API REST y no se usa.

## Chat

El chat responde con los textos guardados, en el idioma elegido. Si el dato no está, lo dice y no lo inventa. El beacon detectado solo aporta el lugar actual: no abre el chat ni borra la conversación. La respuesta por API queda preparada y no está conectada. La voz y el micrófono tampoco.

## Idioma y beacons

El idioma elegido (español, inglés o alemán) se guarda en el dispositivo y vale en todas las pantallas. El escaneo de beacons mantiene el UUID `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0` y abre el lugar cuando el RSSI llega a -60. Una pérdida breve de señal no vuelve a abrir la misma ficha.

## Pruebas

```
flutter test
flutter analyze
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
