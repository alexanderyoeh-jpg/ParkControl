# Publicación Android, iOS y web de ParkControl

## Alcance listo en el código

ParkControl usa un solo proyecto Flutter para los tres canales. Android, iOS
y la plataforma web/PWA consumen la misma API Node detrás de HTTPS. Roles,
planes, suspensión y el aislamiento por `estacionamiento_id` siguen validándose
en el backend; ninguna variante del cliente obtiene permisos propios.

```text
Android ─┐
iOS ─────┼── Flutter ── HTTPS ── API ParkControl ── SQLite hoy / PostgreSQL futuro
Web/PWA ─┘
```

Se incorporaron los identificadores de publicación `cl.parkcontrol.app`, el
icono ParkControl para Android/iOS/web, permiso de Internet para Android de
producción y metadatos PWA. El identificador debe reservarse y verificarse en
Google Play Console y Apple Developer antes de la primera publicación. Si una
tienda lo rechaza por no estar disponible, se cambia **antes** de publicar la
primera versión; no se modifica después de tener usuarios instalados.

## Regla de URL de API

Toda compilación de publicación exige una URL HTTPS explícita:

```text
--dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl
```

La aplicación rechaza al iniciar una compilación `profile` o `release` sin esa
variable o con HTTP. Los valores locales sólo existen para `debug`:

- Android emulador: `http://10.0.2.2:3000` si no se entrega la variable.
- iOS Simulator y navegador local: `http://localhost:3000` si no se entrega
  la variable.
- Teléfono físico: usar staging HTTPS; no abrir HTTP en la versión release.

El navegador añade un encabezado `Origin`; por ello el VPS debe definir, por
ejemplo:

```dotenv
PARKCONTROL_ALLOWED_ORIGINS=https://app.tu-dominio.cl
```

No usar comodines. La aplicación móvil no depende de CORS, pero sí de la misma
API HTTPS y del token de sesión válido.

El Bearer token se conserva sólo en memoria durante una sesión abierta; no se
guarda en `SharedPreferences` ni en el almacenamiento local del navegador. Por
seguridad, después de cerrar completamente la app o recargar la plataforma web
se pide iniciar sesión de nuevo. La cola offline permanece local, pero requiere
que el usuario autorizado vuelva a iniciar sesión para sincronizarla.

La cola offline y la caché operativa sí pueden contener patentes, observaciones
y montos mientras esperan sincronización. En esta etapa usan el almacenamiento
local estándar de la plataforma, no cifrado propio de la aplicación. El piloto
debe usar dispositivos personales o administrados, con bloqueo de pantalla y
cifrado del sistema activo; no se debe operar en computadores públicos o
perfiles de navegador compartidos. No borrar la caché a ciegas: primero se
deben sincronizar o resolver las operaciones pendientes.

## Android

1. Crear el keystore de subida en un lugar privado y respaldarlo cifrado. No
   se puede recuperar una aplicación publicada si se pierde la llave.
2. Copiar `android/key.properties.example` como `android/key.properties`,
   completar las cuatro propiedades y confirmar que ambos archivos de firma
   siguen fuera de Git.
3. Validar primero una compilación debug y luego generar el AAB:

   ```bash
   flutter build appbundle --release \
     --dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl
   ```

4. Subir `build/app/outputs/bundle/release/app-release.aab` a la pista interna
   de Google Play. Probar login, entrada, salida, comprobante Pro, PDF, turno,
   suspensión y reconexión antes de promoverla.

El proyecto bloquea las tareas release sin un keystore válido: nunca firma con
la llave debug. La excepción de tráfico HTTP sólo vive en
`android/app/src/debug`; no se empaqueta en release.

Antes de completar el formulario de Google Play, preparar una política de
privacidad pública y declarar con exactitud la información que realmente trata
el producto: datos de cuenta/administración, patentes, movimientos, cobros y
eventuales datos de soporte. No declarar capacidades de pago que todavía no
estén activas en el backend.

## iOS

La compilación y firma iOS se hacen desde macOS con Xcode y una cuenta Apple
Developer. Windows no puede producir el archivo final de App Store.

1. Abrir `ios/Runner.xcworkspace` después de ejecutar `flutter pub get` en un
   Mac. Asociar el target Runner al equipo Apple, verificar
   `cl.parkcontrol.app` y activar firma automática o la configuración de
   distribución acordada.
2. Generar una IPA de prueba:

   ```bash
   flutter build ipa --release \
     --dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl
   ```

3. Distribuir primero por TestFlight y probar en un iPhone/iPad real. Luego
   enviar a revisión sólo después del checklist de aceptación.

El proyecto incorpora `PrivacyInfo.xcprivacy` para el uso local de
`UserDefaults` de la aplicación. Apple exige además que el titular complete en
App Store Connect la declaración **App Privacy** con los datos reales del
servicio y la política de privacidad. Debe revisarse en cada cambio de SDK o
funcionalidad; no se debe inventar ni omitir categorías de datos.

La declaración de exportación indica que la app no usa criptografía propia no
exenta: la comunicación HTTPS estándar la proporciona el sistema. Si se agrega
cifrado propio o un SDK que lo requiera, esta declaración debe revisarse antes
de enviar una nueva versión.

iOS mantiene ATS por defecto: la API debe presentar TLS válido. No agregar
excepciones de HTTP para resolver un problema de staging.

## Web y PWA

Compilar el sitio en un entorno limpio:

```bash
flutter build web --release \
  --dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl
```

Publicar el contenido de `build/web` en `app.tu-dominio.cl`, nunca en el mismo
directorio que Node o SQLite. La plantilla
[`infra/nginx/parkcontrol-web.conf.example`](../infra/nginx/parkcontrol-web.conf.example)
sirve los archivos, conserva la recarga de rutas Flutter y evita cachear
`index.html`/el service worker de forma permanente.

Probar al menos Chrome, Edge, Firefox y Safari actuales: login por CORS,
recarga, cierre de sesión, entrada/salida, PDF, Excel, modo offline y retorno
de red. La base local web/IndexedDB es una caché y cola: el backend sigue
siendo la fuente de verdad.

## Datos de tarjetas y pagos

ParkControl no recibe ni almacena números CVV, PAN ni tarjetas. Cuando se
active Mercado Pago, el pago se inicia desde el backend y se completa en su
checkout/tokenización oficial. Los métodos transferencia y efectivo mantienen
su registro comercial interno. Ver
[`DECISIONES_COMERCIALES_MERCADOPAGO.md`](DECISIONES_COMERCIALES_MERCADOPAGO.md)
antes de activar cobros automáticos.

## Lista previa a las tiendas y al dominio público

- [ ] VPS staging con API, HTTPS, CORS del dominio web, monitoreo y respaldo
  restaurado en una ubicación aislada.
- [ ] Compilaciones release Android/Web y archive iOS completados con la URL
  HTTPS final; no se usaron URLs locales ni secretos Flutter.
- [ ] Prueba física Android, iPhone/iPad y navegadores indicados.
- [ ] Política de privacidad, URL de soporte, ficha comercial, íconos y
  capturas de las tiendas preparados y revisados por el titular.
- [ ] Declaraciones Google Data Safety y Apple App Privacy realizadas según
  los datos que efectivamente procese la versión enviada.
- [ ] Plan de soporte, recuperación de cuenta, respaldo, monitoreo y rollback
  ensayado antes de aceptar el primer estacionamiento real.
