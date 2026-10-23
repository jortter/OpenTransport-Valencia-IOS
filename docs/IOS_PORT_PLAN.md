# Port a iOS de OpenTransport Valencia: viabilidad y plan

> Documento de planificación. Basado en el estado del repositorio Android en el
> commit `94b7ba6`.

## 1. Resumen

**Es viable a nivel técnico.** La app Android es Kotlin + Jetpack Compose
puro, sin backend propio, y la mayoría de piezas tienen un equivalente directo
en iOS (SwiftUI, MapLibre Native iOS, CoreLocation, WidgetKit).

Los riesgos principales **no son técnicos**:

1. **Las APIs que usa son no oficiales o usan credenciales embebidas.** Esto
   pone en riesgo la publicación en la App Store (ver §5).
2. **Los avisos de llegada en segundo plano** dependen de un bucle de polling
   que en iOS no funciona con la app cerrada.
3. **Para compilar y publicar hacen falta un Mac con Xcode** y una cuenta
   Apple Developer (99 €/año).

Estimación: **unas 8–11 semanas** para una persona con experiencia en Swift
para tener la app de iPhone con paridad funcional, y **unas 3–4 semanas más**
para la app de Apple Watch.

## 2. Qué hay en el proyecto Android

| Módulo | Líneas Kotlin | Contenido |
|---|---|---|
| `app/` | ~6.400 | App móvil |
| `wear/` | ~3.100 | App WearOS independiente (mucho código duplicado de `app/`) |

Ficheros clave de `app/src/main/java/es/emtvalencia/live/`:

| Fichero | Líneas | Función | Dificultad del port |
|---|---|---|---|
| `EmtRepository.kt` | 862 | Todas las llamadas de red y el parseo | Baja–media (traducción casi literal) |
| `TransitData.kt` | 198 | Modelos y carga de los JSON de `assets/` | Baja |
| `TransitMotion.kt` | 144 | Geometría: proyección sobre rutas, distancias, sentido | Baja (matemática pura) |
| `JourneyPlanner.kt` | 211 | Planificador de viajes (algoritmo propio) | Baja |
| `Language.kt` | 134 | Tabla propia de textos ES/EN/VA (77 cadenas) | Baja |
| `EmtApp.kt` | 2.965 | **Toda la UI**: pestañas, hojas, animación de buses, lógica de estado | **Alta** (el grueso del trabajo) |
| `NativeMap.kt` | 967 | Mapa MapLibre: fuentes GeoJSON, capas, clustering, iconos | Media–alta |
| `DraggableSheet.kt` | 137 | Bottom sheet arrastrable propia | Media |
| `Onboarding.kt` | 304 | Pantallas de bienvenida | Baja |
| `Notifier.kt` | 56 | Notificaciones locales | Baja (pero ver §5.2) |
| `StopWidget*`, `Widget*` | ~380 | Widget de pantalla de inicio | Media (WidgetKit es otro modelo) |
| `LineBadgeImage.kt` | 63 | Iconos de línea descargados del geoportal EMT | Baja |

Datos estáticos en `assets/` (~920 KB: `stops.json`, `routes.json`,
`metrovalencia.geojson`, `rodalies.geojson`, `rodalies_times.json`, logos).
**Se reutilizan tal cual** en el bundle de iOS.

### Fuentes de datos externas

| Servicio | Endpoint | Tipo |
|---|---|---|
| EMT tiempo real / estimaciones | `servicios.emtvalencia.es` | API privada con cabecera `X-WSSE` fija y User-Agent de Android |
| EMT avisos | `emtvalencia.es/wp/estado-del-servicio/` | Scraping de HTML |
| EMT iconos de línea | `geoportal.emtvalencia.es/.../create-line-image.php` | Imagen pública |
| Metrovalencia | `metroapi.alexbadi.es`, `fgv.es/.../api/v1`, `wiilink24.com/extras/locations.json` | APIs de terceros / no oficiales |
| Metrovalencia avisos | `metrovalencia.es/.../ajax-no-wp.php` | POST a un endpoint AJAX de WordPress |
| Metrobús | `api.softoursistemas.com/metrobus` | API privada; se hace pasar por la app oficial (`x-requested-with: com.softoursistemas.metgovalencia`) |
| Metrobús avisos | `metgovalencia.com/avisos-de-lineas/` | Scraping de HTML |
| Valenbisi | `api.jcdecaux.com` (apiKey embebida) + `api.cyclocity.fr` (clave de cliente web embebida) | API con claves |
| Rodalies avisos | `gtfsrt.renfe.com/alerts.json` | **Abierta (GTFS-RT oficial)** |
| Rutas a pie | `routing.openstreetmap.de` (OSRM) | Pública (uso razonable) |
| Mapa base | `basemaps.cartocdn.com`, `server.arcgisonline.com` | Teselas públicas con términos de uso |

Todo es HTTPS, así que no hay problemas con App Transport Security.

## 3. Estrategia: opciones

| Opción | Descripción | Ventajas | Inconvenientes |
|---|---|---|---|
| **A. Reescritura nativa (SwiftUI)** | Traducir Kotlin → Swift | Mejor experiencia iOS, WidgetKit/Live Activities/watchOS sin fricción, no toca el repo de tu amigo | Dos bases de código que divergen; cada fix de API hay que hacerlo dos veces |
| **B. Kotlin Multiplatform (KMP) solo para datos** | Pasar `EmtRepository`, modelos, `TransitMotion` y `JourneyPlanner` a un módulo `shared` usado por Android y por una UI SwiftUI | Una única capa de datos (lo que más se rompe cuando cambian las APIs) | Exige reestructurar el repo Android; requiere acuerdo con tu amigo; usa `org.json` y `HttpURLConnection`, que habría que cambiar por `kotlinx.serialization` + Ktor |
| **C. Compose Multiplatform** | Reutilizar también la UI | Máxima reutilización | MapLibre no tiene binding de Compose para iOS, la UI no se siente nativa, y widgets/watch siguen siendo Swift. No compensa aquí |

### Recomendación

**Empezar con la opción A** y diseñar la capa de datos en Swift como un
paquete independiente (`OpenTransportCore`), espejo 1:1 de
`EmtRepository.kt`, para que sea fácil portar los cambios que haga tu amigo.

Pasar a la **opción B** si se ve que los cambios en las APIs son frecuentes y
tu amigo está dispuesto a reestructurar su proyecto. La capa de datos son
unas 1.400 líneas, así que la duplicación es asumible al principio.

## 4. Equivalencias Android → iOS

| Android | iOS |
|---|---|
| Jetpack Compose + Material3 | SwiftUI (iOS 17+) |
| Corrutinas (`async`/`awaitAll`, `withContext(IO)`) | `async`/`await`, `async let`, `TaskGroup` |
| `HttpURLConnection` + `org.json` | `URLSession` + `Codable` / `JSONSerialization` |
| Regex de scraping HTML | `Regex` de Swift 5.7+ (mismos patrones) o SwiftSoup |
| MapLibre Android 13.x | **MapLibre Native iOS** (SPM `maplibre-gl-native-distribution`), con las mismas URLs de estilo y capas |
| `play-services-location` | CoreLocation (`CLLocationManager` / `CLLocationUpdate.liveUpdates`) |
| `SharedPreferences` | `UserDefaults`, en un *App Group* compartido con el widget y el reloj |
| `DraggableSheet` propio | `.sheet` con `presentationDetents` + `presentationBackgroundInteraction(.enabled)` |
| `NotificationCompat` | `UserNotifications` (notificaciones locales) |
| App widget (`RemoteViews`) | **WidgetKit** + `AppIntent` para el botón de refrescar (iOS 17) |
| Tabla `Strings` ES/EN/VA | Struct `Strings` equivalente, o String Catalog (`.xcstrings`) con `es`, `en`, `ca-ES-valencia` |
| Intent a Google Maps | `MKMapItem.openInMaps` (Apple Maps), con Google Maps como opción |
| Compartir parada | `ShareLink` |
| Tema claro/oscuro/auto | `preferredColorScheme` |
| WearOS app + Tile + Complication | App watchOS + widgets de WidgetKit (complicaciones y Smart Stack) |

## 5. Riesgos y bloqueos

### 5.1 App Store y APIs no oficiales (riesgo ALTO)

- La regla **5.2.2** de la App Store Review Guidelines obliga a tener permiso
  para usar servicios de terceros. La app usa credenciales embebidas (WSSE de
  EMT, claves de JCDecaux/Cyclocity), se hace pasar por la app de Softour
  (Metrobús) y hace scraping de webs. En Android, con distribución por APK, esto
  importa menos; **en la App Store puede acabar en rechazo o retirada** si un
  operador se queja.
- El User-Agent `Dalvik/... Pixel 8a` desde un iPhone es raro. Probablemente
  funcione igual, pero hay que probarlo, porque EMT podría filtrar por él.
- Las credenciales son las mismas que en el repo público: cualquiera puede
  extraerlas, y si un operador las revoca se rompen Android e iOS a la vez.
- **Nombre e identidad:** el `applicationId` es `es.emtvalencia.live`. En iOS
  hay que usar un bundle ID propio (p. ej. `com.<tuusuario>.opentransport`) y
  no usar marcas ni logos de EMT, FGV o Renfe de forma que la app parezca
  oficial (reglas 4.1 y 5.2.1).

**Mitigaciones:**
- Pedir acceso oficial: EMT València y FGV tienen portales de datos abiertos;
  la Generalitat y Renfe publican GTFS. Valenbisi tiene la API abierta de
  JCDecaux (con registro gratuito y clave propia).
- Pensar en un **pequeño backend/proxy** que concentre las credenciales y el
  scraping (también resuelve §5.2).
- Mientras tanto, distribuir por **TestFlight** (hasta 10.000 testers, con una
  revisión más ligera) antes de intentar publicar en la App Store.

### 5.2 Avisos de llegada en segundo plano (riesgo MEDIO)

En Android, `EmtApp.kt` (líneas 174–205) ejecuta un `while (true)` que
consulta los tiempos de llegada y lanza la notificación. iOS suspende la app
pocos segundos después de pasar a segundo plano, así que esto **no funciona
igual**.

Opciones, de menos a más esfuerzo:
1. Avisos solo con la app abierta (y unos ~30 s en segundo plano con
   `beginBackgroundTask`).
2. `BGAppRefreshTask`: iOS decide cuándo se ejecuta (como mucho cada 15 min y
   sin garantías). No sirve para un "llega en 3 min".
3. **Live Activity** (pantalla de bloqueo y Dynamic Island) al seguir una
   línea: es la experiencia ideal en iOS, pero para actualizarse con la app
   cerrada necesita **push desde un servidor**.
4. Backend que haga el polling y envíe pushes (APNs).

Recomendación: opción 1 en el MVP y opciones 3+4 si se monta el backend.

### 5.3 Widgets (riesgo BAJO–MEDIO)

WidgetKit funciona con *timelines* y un presupuesto de unas 40–70
actualizaciones al día, así que no puede refrescar cada minuto. Solución: el
widget guarda la hora de llegada absoluta y muestra la cuenta atrás con
`Text(date, style: .timer)`, y el botón de refrescar (`AppIntent`) fuerza una
recarga.

### 5.4 Apple Watch (riesgo MEDIO)

- MapLibre **no es compatible con watchOS**. El mapa del reloj tendría que usar
  MapKit (`Map` de SwiftUI en watchOS 10+), sin el estilo de Carto.
- Los Tiles de WearOS no existen en watchOS. Su equivalente más cercano son los
  widgets del Smart Stack. Las complicaciones también se hacen con WidgetKit.

### 5.5 Entorno de desarrollo

- Hace falta macOS + Xcode 16+ para compilar, firmar y usar el simulador.
  Desde Linux solo se puede escribir y probar la capa de datos si es un paquete
  Swift sin UIKit/SwiftUI (`swift test` funciona en Linux).
- Para la integración continua se pueden usar runners `macos-latest` de GitHub
  Actions.
- Cuenta Apple Developer: 99 €/año (para TestFlight y la App Store).

### 5.6 Licencia

El fichero `LICENSE` es una MIT con copyright de **650 Industries (Expo)**, que
parece copiado de otro proyecto. Conviene pedirle a tu amigo que aclare la
licencia (o que ponga una MIT a su nombre) antes de redistribuir un derivado.

## 6. Arquitectura propuesta

```text
ios/
  OpenTransport.xcodeproj
  Packages/
    OpenTransportCore/          # Swift Package, sin dependencias de UI (testeable en Linux)
      Sources/OpenTransportCore/
        Models/                 # ← TransitData.kt (Stop, BusRoute, Arrival, Place, Incident…)
        Data/TransitDataLoader  # ← carga de stops.json / routes.json / geojson
        Network/
          EmtClient.swift       # ← EmtRepository: buses, stop, nextBus, incidents
          MetroClient.swift     # ← metroStations, metroArrivals, fgvIncidents
          MetrobusClient.swift  # ← metrobus*
          ValenbisiClient.swift # ← valenbisi, valenbisiBikes, cyclocityToken
          RodaliesClient.swift  # ← rodaliesNetwork, rodaliesIncidents
          WalkRouting.swift     # ← walkMetrics (OSRM)
        Motion/TransitMotion    # ← TransitMotion.kt
        Planner/JourneyPlanner  # ← JourneyPlanner.kt
        Strings.swift           # ← Language.kt
      Tests/                    # Tests de parseo con respuestas JSON/HTML grabadas
  OpenTransport/                # App iOS (SwiftUI)
    App/ AppState (ObservableObject / @Observable) ← estado que hoy vive en EmtApp()
    Map/ TransitMapView (UIViewRepresentable sobre MLNMapView) ← NativeMap.kt
    Features/ Map, Saved, Alerts, Plan, Settings, Onboarding, StopSheet, LineSheet, FollowSheet…
    Resources/ assets JSON + logos (copiados de app/src/main/assets)
  OpenTransportWidget/          # WidgetKit
  OpenTransportWatch/           # watchOS (fase 2)
```

Decisiones:
- **iOS 17 como mínimo** (`@Observable`, widgets interactivos, detents de
  sheet maduros). Cubre más del 90 % de los iPhone en uso.
- Mantener los **mismos nombres de funciones y modelos** que en Kotlin para que
  sea fácil comparar los dos códigos al portar cambios.
- Al portar `EmtApp.kt`, separar el estado y la lógica (merge y animación de
  buses, polling) de la vista en un `AppState`. El fichero Kotlin lo mezcla todo
  en un único composable de unas 3.000 líneas.

## 7. Plan por fases

| Fase | Contenido | Estimación |
|---|---|---|
| **0. Preparación** | Proyecto Xcode, SPM con MapLibre, App Group, CI en macOS, copiar los assets. Comprobar con `curl` cada endpoint usando cabeceras de iOS | 0,5 sem |
| **1. Núcleo de datos** | `OpenTransportCore`: modelos, carga de assets, todos los clientes de red, `TransitMotion`, `JourneyPlanner`, `Strings`. Tests con fixtures | 1,5–2 sem |
| **2. Mapa** | `TransitMapView`: estilos claro/oscuro/satélite, capas de paradas con clustering, rutas ida/vuelta, Metro/Rodalies/Metrobús, buses en vivo animados, usuario, viaje, capas configurables | 2–3 sem |
| **3. Pantallas** | Pestañas Mapa / Guardadas / Avisos / Planificar / Ajustes, búsqueda, hojas de parada, línea, seguimiento, Valenbisi, Metrobús y Rodalies, onboarding, idioma, tema | 2–3 sem |
| **4. Integraciones iOS** | Notificaciones locales (en primer plano), widget WidgetKit con configuración por `AppIntent`, compartir y abrir en Mapas | 1,5–2 sem |
| **5. Pulido y distribución** | Accesibilidad (Dynamic Type, VoiceOver), iconos, capturas, TestFlight | 1 sem |
| **6. Apple Watch** *(opcional)* | App watchOS con MapKit, cercanas, favoritas, complicaciones y widget de Smart Stack | 3–4 sem |
| **7. Backend** *(opcional)* | Proxy de APIs + APNs para avisos y Live Activities en segundo plano | 2–3 sem |

**MVP recomendado** (fases 0–3 + notificaciones básicas): unas 6–8 semanas.

## 8. Primeros pasos concretos

1. Hablar con tu amigo sobre: licencia, nombre/branding, si le interesa
   KMP a medio plazo, y si se puede pedir acceso oficial a las APIs.
2. Verificar desde un iPhone/simulador (o `curl` con UA de iOS) que
   `servicios.emtvalencia.es` acepta las peticiones.
3. Crear `ios/Packages/OpenTransportCore` y portar `TransitData.kt` +
   `TransitMotion.kt` + `EmtRepository.buses/stop` con tests. Esto valida la
   parte más crítica (tiempo real EMT) antes de invertir en UI.
4. Prototipo de mapa con MapLibre iOS mostrando paradas y buses de una línea.
