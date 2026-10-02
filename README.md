# Memora para iPhone

Proyecto **nativo SwiftUI** para abrir en Xcode. Esta entrega es Memora iOS **0.5.0**, build **5** (actualización con arquitectura de diseño adaptable responsive basado en referencia 393 pt sin anchos rígidos). La interfaz sigue las referencias entregadas, usa el espacio completo y ofrece rutas funcionales desde Configuración para cuenta, contraseña, cifrado, sesiones, privacidad, biblioteca, almacenamiento, bóveda y apariencia. Se instala vacía; no contiene fotos, personas, álbumes ni contadores ficticios.

## Abrir y compilar

1. Copia esta carpeta a un Mac con **Xcode 16 o posterior**.
2. Abre `Memora.xcodeproj` y selecciona el esquema **Memora**.
3. En **Signing & Capabilities**, elige tu equipo de desarrollo. Si Xcode indica que `app.memora.native` está ocupado, cambia el *Bundle Identifier* por uno propio.
4. Selecciona un simulador iPhone con **iOS 17 o posterior** y pulsa **⌘B** para compilar; pulsa **⌘R** para ejecutar.
5. Para instalar en un iPhone físico, selecciona el dispositivo y configura la firma con tu Apple ID/equipo.

No requiere CocoaPods, Expo, Node.js, Cloudflare ni servicios externos. Este proyecto se preparó en Windows: se validaron la estructura `.xcodeproj` y la sintaxis Swift, pero **no se pudo ejecutar `xcodebuild`** aquí. La primera compilación y la prueba de Face ID requieren un Mac y un iPhone compatible.

## Vista local

La carpeta `../Memora-iOS-preview` contiene una vista local funcional para abrir en `localhost` desde Windows. Incluye cuenta local, bloqueo por intentos e inactividad, bóveda, importación de inventario, álbumes, personas, búsqueda y configuración persistente. No es una PWA, no instala service worker y no reemplaza la compilación nativa.

## Funciones presentes

- Registro, inicio de sesión y recuperación **locales**. La contraseña tiene al menos 12 caracteres. Tras cinco intentos fallidos se impone una espera de 30 segundos.
- Inicio de sesión persistente activado de forma predeterminada. La clave de sesión se guarda en Keychain con acceso limitado a este dispositivo, se verifica al abrir la biblioteca y se elimina al cerrar sesión. Puede desactivarse desde Configuración → Dispositivos y sesiones.
- Clave raíz aleatoria envuelta con una clave derivada de la contraseña mediante PBKDF2-HMAC-SHA256. El código de recuperación envuelve la misma clave por separado; se muestra una vez y rota al usarlo.
- Metadatos cifrados; cada original recibe una clave individual AES-256-GCM. Las claves de archivo se envuelven con una clave derivada de la cuenta. Los archivos se guardan con protección de datos de iOS.
- Importación desde Fotos y Archivos, deduplicación por SHA-256, miniaturas cifradas, álbumes, secciones, personas manuales, favoritos, búsqueda por texto, papelera y restauración. Un asset puede pertenecer a varios álbumes sin duplicar el original.
- Vista previa de originales con Quick Look y exportación mediante la hoja de compartir. Las copias temporales se eliminan al cerrar esas hojas y al bloquear la bóveda o cerrar sesión.
- Bóveda con clave maestra, contraseña y código de recuperación diferentes. Puede usar Face ID mediante Keychain si el dispositivo lo admite. Se bloquea al salir de la app o tras 15 minutos.

## Límites de esta versión

- La cuenta y todos sus datos existen **solo en ese iPhone**. El correo sirve como identificador local; no se verifica ni se envía email. No hay copia remota ni sincronización con Cloudflare.
- El reconocimiento facial, embeddings y búsqueda por fotografía siguen pendientes. Los perfiles de personas son manuales.
- La importación carga hasta **50 MB por archivo**. Algunos videos/RAW/HEIC dependen de las representaciones y códecs ofrecidos por iOS; una selección que iOS no entregue como datos no se importa. La fecha de captura original y los metadatos EXIF no se extraen todavía.
- Los datos de la antigua PWA no se transfieren a esta app. El sitio PWA de Cloudflare se retiró tras confirmar que no había archivos reales que migrar.
- El cifrado y la persistencia necesitan pruebas de compilación y en dispositivo antes de usarse como único respaldo de recuerdos importantes. Este código no ha tenido auditoría criptográfica.

La implementación está en `Memora/MemoryStore.swift` y `Memora/Security.swift`; la interfaz se encuentra en `Memora/Views/`. Los ajustes de compilación y firma están en `Memora.xcodeproj/project.pbxproj`.
