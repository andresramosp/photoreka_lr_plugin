# Script para abrir el log del plugin Photoreka
# Ejecutar con: .\ver-log.ps1

$logPath = "$env:APPDATA\Adobe\Lightroom\Logs\PhotorekaPlugin.log"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHOTOREKA PLUGIN - VISOR DE LOGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si el archivo existe
if (Test-Path $logPath) {
    Write-Host "✓ Log encontrado en:" -ForegroundColor Green
    Write-Host "  $logPath" -ForegroundColor Gray
    Write-Host ""
    
    # Mostrar tamaño del archivo
    $fileInfo = Get-Item $logPath
    $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
    Write-Host "Tamaño: $sizeKB KB" -ForegroundColor Yellow
    Write-Host "Última modificación: $($fileInfo.LastWriteTime)" -ForegroundColor Yellow
    Write-Host ""
    
    # Preguntar qué hacer
    Write-Host "¿Qué deseas hacer?" -ForegroundColor Cyan
    Write-Host "  1. Abrir en Notepad"
    Write-Host "  2. Ver últimas 50 líneas"
    Write-Host "  3. Ver en tiempo real (tail -f)"
    Write-Host "  4. Copiar ruta al portapapeles"
    Write-Host "  5. Abrir carpeta de logs"
    Write-Host ""
    
    $choice = Read-Host "Opción (1-5)"
    
    switch ($choice) {
        "1" {
            Write-Host "Abriendo en Notepad..." -ForegroundColor Green
            notepad $logPath
        }
        "2" {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "ÚLTIMAS 50 LÍNEAS" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Get-Content $logPath -Tail 50
        }
        "3" {
            Write-Host ""
            Write-Host "Mostrando log en tiempo real..." -ForegroundColor Green
            Write-Host "Presiona Ctrl+C para salir" -ForegroundColor Yellow
            Write-Host ""
            Get-Content $logPath -Wait -Tail 50
        }
        "4" {
            Set-Clipboard -Value $logPath
            Write-Host "✓ Ruta copiada al portapapeles" -ForegroundColor Green
        }
        "5" {
            $logFolder = Split-Path $logPath
            Write-Host "Abriendo carpeta..." -ForegroundColor Green
            explorer $logFolder
        }
        default {
            Write-Host "Opción inválida" -ForegroundColor Red
        }
    }
    
} else {
    Write-Host "✗ Log no encontrado en:" -ForegroundColor Red
    Write-Host "  $logPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Posibles razones:" -ForegroundColor Yellow
    Write-Host "  - El plugin aún no se ha ejecutado"
    Write-Host "  - Lightroom no está instalado"
    Write-Host "  - La ruta de logs es diferente"
    Write-Host ""
    Write-Host "¿Deseas buscar el log en otra ubicación? (S/N)" -ForegroundColor Cyan
    $search = Read-Host
    
    if ($search -eq "S" -or $search -eq "s") {
        Write-Host ""
        Write-Host "Buscando archivos PhotorekaPlugin.log..." -ForegroundColor Yellow
        Get-ChildItem -Path "$env:APPDATA\Adobe" -Recurse -Filter "PhotorekaPlugin.log" -ErrorAction SilentlyContinue | 
            ForEach-Object { Write-Host "Encontrado: $($_.FullName)" -ForegroundColor Green }
    }
}

Write-Host ""
Write-Host "Presiona cualquier tecla para salir..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
