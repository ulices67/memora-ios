# Script interactivo para subir Memora iOS a GitHub y activar la compilación en la nube
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   🚀 Preparar y Subir Memora iOS a GitHub Actions" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si git está instalado
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Error: Git no está instalado o no se encuentra en el PATH." -ForegroundColor Red
    Write-Host "Por favor instala Git desde https://git-scm.com/ e inténtalo de nuevo." -ForegroundColor Yellow
    exit 1
}

# Inicializar git si no existe
if (-not (Test-Path ".git")) {
    git init
    git branch -M main
}

# Agregar todos los archivos
Write-Host "📦 Indexando archivos del proyecto..." -ForegroundColor Green
git add .

# Verificar si hay cambios para commitear
$status = git status --porcelain
if ($status) {
    git commit -m "feat: Proyecto nativo Memora iOS y workflow de GitHub Actions"
    Write-Host "✅ Commit local generado exitosamente." -ForegroundColor Green
} else {
    Write-Host "ℹ️ Los archivos ya estaban en el commit más reciente." -ForegroundColor Gray
}

# Verificar o solicitar remote origin
$remote = git remote get-url origin 2>$null
if (-not $remote) {
    Write-Host ""
    Write-Host "👉 Ingresa la URL de tu repositorio de GitHub." -ForegroundColor Yellow
    Write-Host "   (Por ejemplo: https://github.com/tu-usuario/memora-ios.git)" -ForegroundColor Gray
    Write-Host "   Si aún no lo creas, créalo primero en: https://github.com/new" -ForegroundColor Gray
    Write-Host ""
    $url = Read-Host "URL del repositorio remoto"
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Host "❌ No se proporcionó ninguna URL. Operación pausada." -ForegroundColor Yellow
        Write-Host "Puedes ejecutar más tarde: git remote add origin <URL> y git push -u origin main" -ForegroundColor Gray
        exit 0
    }
    git remote add origin $url.Trim()
}

Write-Host ""
Write-Host "⬆️ Subiendo cambios a GitHub (rama main)..." -ForegroundColor Cyan
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "   🎉 ¡PROYECTO SUBIDO CON ÉXITO A GITHUB!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Abre tu repositorio en GitHub y ve a la pestaña 'Actions'." -ForegroundColor White
    Write-Host "2. Verás el flujo 'Build Memora iOS (.ipa & .app)' compilando con macOS y Xcode 16." -ForegroundColor White
    Write-Host "3. Al terminar (~2-3 min), descarga tu archivo 'Memora-iOS-Device-ipa'." -ForegroundColor White
    Write-Host "4. Consulta 'GUIA_GITHUB_ACTIONS.md' para instalarlo gratis en tu iPhone con Sideloadly." -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "⚠️ Hubo un error al hacer 'git push'. Si te pide autenticación, asegúrate de ingresar tu Personal Access Token (PAT) de GitHub o tus credenciales." -ForegroundColor Yellow
}
