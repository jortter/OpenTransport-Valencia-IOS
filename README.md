<p align="center">
	<img src="app/src/main/assets/OpenTransport_logo.png" alt="Logo de OpenTransport Valencia" width="180">
</p>

# OpenTransport Valencia para iOS

Aplicación nativa para iPhone (SwiftUI) para consultar el transporte público
de València en tiempo real. Es un port de la aplicación Android
[OpenTransport Valencia](https://github.com/Humanoidear/OpenTransport-Valencia),
de la que este repositorio es un fork: comparte con ella los datos estáticos
(paradas, recorridos, logos) y las mismas fuentes de datos.

## Funciones

- **Mapa** con EMT, Metrovalencia, Valenbisi, Metrobús y Rodalies: capas y
  estilo configurables, vista 3D, brújula, "mi ubicación" y paradas cercanas.
- **Autobuses EMT en directo**, animados sobre su recorrido; seguir un bus con
  la cámara detrás (2D o 3D) y ver sus próximas paradas.
- **Autobuses de Metrobús en directo** de las líneas de la parada seleccionada,
  con destino y ocupación.
- **Paradas y estaciones**: llegadas en directo de EMT, Metro y Metrobús
  (con ocupación y horario completo), bicis y anclajes de Valenbisi y horario
  de Rodalies.
- **Planificador de viajes** (beta) con EMT, Metro y Metrobús, esperas reales
  y el viaje dibujado en el mapa.
- **Buscador** de paradas, líneas y estaciones.
- **Guardadas** de todas las redes con la próxima llegada.
- **Avisos del servicio** de EMT, Metrovalencia, Metrobús y Rodalies.
- **Avisos de llegada**: notificación cuando el bus elegido está a unos minutos
  (mientras la app está abierta).
- **Widget** de pantalla de inicio con las próximas llegadas de una parada,
  también en los estilos tintado y transparente.
- Diseño **Liquid Glass** en iOS 26 o posterior, temas claro/oscuro/automático
  e idiomas castellano, valenciano e inglés.

Los datos dependen de la disponibilidad de los servicios externos y pueden no
coincidir exactamente con la situación en la calle.

## Capturas de pantalla

<!-- Capturas de un iPhone real: screenshots/ios/ -->

## Instalar en el iPhone (gratis, sin Mac)

La app se instala con [SideStore](https://docs.sidestore.io) y un Apple ID
gratuito:

1. Instala SideStore siguiendo su guía (solo la primera vez hace falta un
   ordenador, vale Windows o Linux).
2. En el iPhone, abre en Safari
   <https://github.com/jortter/OpenTransport-Valencia-iOS/raw/ios-build/OpenTransport.ipa>.
3. Abre el `.ipa` con SideStore (Compartir → SideStore, o *My Apps* → `+`).
   Si pregunta por las extensiones, elige mantenerlas para tener el widget.
4. Con un Apple ID gratuito la firma dura 7 días: activa el refresco en
   segundo plano de SideStore o pulsa *Refresh All* de vez en cuando.

Requiere iOS 17 o posterior.

## Compilación

No hace falta un Mac: cada push que toca `ios/` lanza
[`.github/workflows/ios.yml`](.github/workflows/ios.yml) en un runner macOS de
GitHub Actions, que:

1. Ejecuta los tests de `OpenTransportCore`.
2. Genera el proyecto con XcodeGen y compila la app para el simulador, con
   capturas automáticas en la rama `ci-screenshots`.
3. Compila un `.ipa` sin firmar y lo publica en la rama `ios-build`.

Con un Mac:

```sh
brew install xcodegen
cd ios && xcodegen generate && open OpenTransport.xcodeproj
```

Los tests de la lógica (sin interfaz) también funcionan en Linux:

```sh
cd ios/Packages/OpenTransportCore && swift test
```

## Estructura

```text
ios/
  project.yml                  Proyecto Xcode (XcodeGen); el .xcodeproj se genera.
  Packages/OpenTransportCore/  Datos, red y lógica, sin interfaz (Swift Package).
  OpenTransport/               App SwiftUI: mapa MapLibre, pestañas y hojas.
  OpenTransportWidget/         Widget (WidgetKit).
app/src/main/assets/           Datos estáticos compartidos con la app Android.
```

La app Android original (`app/` y `wear/`) sigue en el repositorio; su
documentación está en el [repositorio original](https://github.com/Humanoidear/OpenTransport-Valencia).

## Fuentes de datos

Servicios públicos y APIs de EMT València, Metrovalencia (FGV), Valenbisi
(JCDecaux), Metrobús (Softour) y Renfe/Rodalies; recorridos a pie con OSRM
sobre OpenStreetMap. Aplicación no oficial, sin relación con estos operadores.
