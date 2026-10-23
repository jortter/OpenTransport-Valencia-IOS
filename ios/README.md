# OpenTransport Valencia para iOS

Port a iOS (SwiftUI) de la app Android de este repositorio. Ver el plan en
[`docs/IOS_PORT_PLAN.md`](../docs/IOS_PORT_PLAN.md).

## Funciones (paridad con Android)

- Mapa MapLibre con EMT, Metrovalencia, Valenbisi, Metrobús y Rodalies; capas
  y estilo del mapa configurables, vista 3D, brújula y "mi ubicación".
- Paradas EMT con llegadas en directo, bus más cercano, avisos de sus líneas,
  compartir y abrir en Mapas.
- Líneas con recorrido ida/vuelta y buses en directo animados; seguir un bus
  con la cámara detrás (2D/3D) y sus próximas paradas.
- Estaciones de Metro (llegadas en directo), Valenbisi (bicis, anclajes y
  bicis ancladas), Metrobús (llegadas con ocupación y horario) y Rodalies
  (horario de las próximas 3 h).
- Buscador de paradas, líneas y estaciones; paradas cercanas.
- Guardadas de todas las redes con la próxima llegada.
- Avisos del servicio de todas las redes con filtro.
- Avisos de llegada (campana) con notificaciones mientras la app está activa.
- Planificador de viajes (beta) con el viaje dibujado en el mapa.
- Onboarding, idiomas ES/EN/VA, tema claro/oscuro/automático.
- Widget de pantalla de inicio con las próximas llegadas de una parada.

## Estructura

```text
ios/
  project.yml                  Proyecto Xcode (XcodeGen). El .xcodeproj se genera, no se versiona.
  Packages/OpenTransportCore/  Datos, red y lógica (port de EmtRepository, TransitData, TransitMotion…)
  OpenTransport/               App SwiftUI (mapa MapLibre, pestañas, hojas)
  OpenTransportWidget/         Widget (WidgetKit)
```

Los datos estáticos (`stops.json`, `routes.json`, geojson, logos) se leen
directamente de `app/src/main/assets`, compartidos con Android.

## Compilación (sin Mac)

Cada push que toque `ios/` lanza el workflow `.github/workflows/ios.yml` en un
runner macOS de GitHub Actions, que:

1. Ejecuta los tests de `OpenTransportCore`.
2. Compila la app para el simulador y hace capturas → rama `ci-screenshots`.
3. Compila un `.ipa` sin firmar → rama `ios-build` (y pre-release `ios-latest`
   cuando GitHub lo permite).

## Instalar en el iPhone con SideStore (gratis)

1. Instala SideStore siguiendo <https://docs.sidestore.io> (solo la primera
   vez hace falta un ordenador; vale Windows o Linux).
2. En el iPhone, abre en Safari
   <https://github.com/jortter/OpenTransport-Valencia-IOS/raw/ios-build/OpenTransport.ipa>
   y descarga `OpenTransport.ipa`.
3. Ábrelo con SideStore (Compartir → SideStore, o desde *My Apps* → `+`).
4. SideStore renueva la firma cada 7 días; actívale el refresco en segundo
   plano o abre SideStore de vez en cuando y pulsa *Refresh All*.

## Desarrollo con Mac (opcional)

```sh
brew install xcodegen
cd ios && xcodegen generate && open OpenTransport.xcodeproj
```
