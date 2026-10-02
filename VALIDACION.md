# Validación · Memora iOS 0.4.0

- Versión actualizada a `MARKETING_VERSION = 0.4.0` y `CURRENT_PROJECT_VERSION = 4`.
- Sesión persistente nativa añadida mediante Keychain (`AfterFirstUnlockThisDeviceOnly`), restauración verificada al iniciar y revocación al cerrar sesión.
- Control funcional “Mantener sesión iniciada” añadido a Configuración → Dispositivos y sesiones.
- Configuración enlazada con pantallas funcionales de perfil, contraseña, sesiones, cifrado, privacidad, biblioteca, almacenamiento y bóveda.
- Vista localhost adaptada a `100dvh`, áreas seguras de iOS, teclado y navegación inferior fija sin recortar contenido.
- Motor local de la vista reforzado con credenciales mediante Web Crypto, bloqueo tras cinco intentos, cierre por inactividad, PIN separado para la bóveda y exportación del índice sin hashes legibles.
- UI ajustada para usar el ancho disponible del iPhone; se eliminó el límite estrecho de login y se aumentó la altura táctil de campos, filas y botones.
- Acciones del detalle de archivo reorganizadas como botones de ancho completo con iconos.
- Corregida la lectura de assets seguros en el detalle de archivo para evitar una expresión Swift ambigua.
- Vista local agregada en `outputs/Memora-iOS-preview` para revisar login y navegación desde `localhost` sin PWA.
- Ocho archivos Swift revisados con comprobaciones estructurales desde Windows.
- `Memora.xcscheme`, `Contents.json` e icono de 1024 × 1024 actualizado con el nuevo diseño dorado de galería privada.
- Cloudflare Pages: se eliminó el proyecto `memora-biblioteca` y se verificó que ya no aparece en la lista de proyectos.
- **Pendiente en Mac:** `xcodebuild`, ejecución en simulador, registro/inicio de sesión, importación, Quick Look, recuperación, bloqueo y Face ID en dispositivo físico.

La validación de sintaxis no equivale a una compilación de Xcode. No se generó un `.ipa`.
