# Guía de Compilación en la Nube con GitHub Actions

Esta carpeta ya incluye la configuración lista en `.github/workflows/build-ios.yml` para compilar **Memora** en los servidores oficiales de Apple de GitHub Actions (**macOS Sonoma con Xcode 16**) y entregarte los ejecutables directamente descargables.

---

## ⚡ ¿Por qué GitHub Actions?

- **Sin Mac local**: Todo el proceso de `xcodebuild` se ejecuta en servidores Mac oficiales de Apple en la nube.
- **Gratuito**: En repositorios públicos es 100% gratuito. En repositorios privados incluye 2,000 minutos al mes (cada compilación tarda ~2 a 3 minutos).
- **Dos salidas automáticas**:
  1. `Memora.ipa` (para instalar en tu iPhone físico mediante Sideloadly, AltStore o TrollStore).
  2. `Memora-Simulator.app.zip` (para arrastrar a cualquier simulador iOS).

---

## 🚀 Paso 1: Subir el proyecto a GitHub

### Opción Rápida con PowerShell
Hemos creado un script que lo hace guiado. Abre PowerShell en esta carpeta y ejecuta:
```powershell
.\subir-a-github.ps1
```

---

### Opción Manual con Git

1. Ve a [github.com/new](https://github.com/new) y crea un nuevo repositorio (puedes nombrarlo `memora-ios` y elegir **Público** o **Privado**). **No** marques las casillas de agregar README ni .gitignore (ya los tenemos aquí).
2. Abre PowerShell o terminal en esta carpeta (`outputs\Memora-iOS`) y corre:

```powershell
git add .
git commit -m "feat: Proyecto Memora iOS y workflow de compilación en Xcode 16"
git remote add origin https://github.com/TU_USUARIO/TU_REPOSITORIO.git
git push -u origin main
```
*(Reemplaza `https://github.com/TU_USUARIO/TU_REPOSITORIO.git` por la URL de tu repositorio recién creado)*.

---

## 📥 Paso 2: Descargar el `.ipa` compilado

1. En tu repositorio de GitHub, haz clic en la pestaña **Actions** (en la barra superior).
2. Verás el flujo **"Build Memora iOS (.ipa & .app)"** ejecutándose (icono amarillo girando).
3. Espera entre **2 y 3 minutos** hasta que aparezca una marca verde de éxito ✅.
4. Haz clic en la ejecución y baja hasta la sección **Artifacts** (al final de la página).
5. Descarga:
   - **`Memora-iOS-Device-ipa`** (contiene `Memora.ipa` para tu iPhone).
   - O **`Memora-iOS-Simulator-app`** (si deseas probar en simulador).

---

## 📲 Paso 3: Instalar `Memora.ipa` en tu iPhone desde Windows

No necesitas cuenta de desarrollador de Apple de pago ($99 USD). Puedes instalarlo gratis usando tu Apple ID personal con cualquiera de estas opciones:

### Método Recomendado: Sideloadly (Windows)
1. Descarga e instala **[Sideloadly](https://sideloadly.io/)** en tu PC con Windows (asegúrate de tener instalado iTunes o los controladores de Apple que Sideloadly sugiere).
2. Conecta tu iPhone a la PC mediante cable USB (si el iPhone pregunta *"¿Confiar en esta computadora?"*, pulsa **Confiar**).
3. Abre Sideloadly:
   - Verás tu iPhone detectado en el campo *iDevice*.
   - Arrastra el archivo `Memora.ipa` a la ventana de Sideloadly.
   - En *Apple ID*, escribe tu correo de Apple ID habitual.
   - Haz clic en **Start**. Sideloadly firmará la app temporalmente y la instalará en tu iPhone.
4. **En tu iPhone (primer inicio):**
   - Ve a **Ajustes** > **General** > **VPN y gestión de dispositivos**.
   - Toca tu Apple ID y pulsa **Confiar**.
   - En iOS 16, 17 o 18: Si el sistema te lo pide, activa el **Modo de desarrollo** en *Ajustes > Privacidad y seguridad > Modo de desarrollo* y reinicia el iPhone.
5. ¡Listo! Abre **Memora** en tu pantalla de inicio con fondo negro, diseño nativo SwiftUI, cifrado AES-256-GCM y Face ID habilitado.
