<# :
@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$Archivo='%~f0'; & ([scriptblock]::Create([IO.File]::ReadAllText($Archivo,[Text.Encoding]::UTF8))) %*"
exit /b
#>
# ================================
#  Optimizador Windows - J.vps  v3
# ================================
# Archivo único: arriba un lanzador .bat, abajo el programa en PowerShell.
# Uso: doble clic (pide permisos de administrador solo)
# Para probar sin ventana:  Optimizador.bat -Accion diagnostico | limpieza -Simular
# Para sacar una captura:   Optimizador.bat -Captura C:\ruta\captura.png
param(
    [ValidateSet('', 'limpieza', 'juego', 'todo', 'diagnostico', 'reparar', 'red', 'restaurar', 'autojuego', 'finjuego', 'routerprobar')]
    [string]$Accion = '',
    [switch]$Simular,
    [string]$Captura = '',
    [string]$Tema = '',     # solo para capturas de prueba
    [string]$Estilo = '',   # idem: Solido, Vidrio, Neon
    [string]$Tamano = '',   # idem: Completo, Compacto
    [switch]$Claro,
    [string]$SinDatos = '', # solo para capturas de prueba: ej. 'ram,vram'
    [string]$Vista = '',    # solo para capturas de prueba: 'rendimiento' saca la pestaña Rendimiento
    [switch]$SinElevar,     # lo pasa Optimizador.exe: ya pidió permisos él (con su nombre y la paloma)
    [switch]$Bandeja,       # lo pasa la tarea de "Iniciar con Windows" (se llama así por la versión que abría en la bandeja)
    [switch]$Desinstalar    # desde Configuración > Aplicaciones > Desinstalar
)

$ErrorActionPreference = 'SilentlyContinue'
# los logs van a AppData para no ensuciar la carpeta del optimizador
$Raiz = Join-Path $env:LOCALAPPDATA 'Optimizador J.vps'
$Version = '3.63'
# el programa tal cual se abrió: si corre desde la copia instalada y la desinstalan, Instalar la reescribe desde acá
$Fuente = try { [IO.File]::ReadAllBytes($Archivo) } catch { $null }

#incluir sistema/instancia.ps1
#incluir sistema/instalacion.ps1
#incluir sistema/actualizaciones.ps1
#incluir sistema/admin.ps1
#incluir nucleo/nativo.ps1
#incluir nucleo/inicio-windows.ps1
#incluir nucleo/espacio.ps1
#incluir nucleo/core.ps1

# ================================
# MODO CONSOLA (pruebas)
# ================================

if ($Accion) {
    $sync = $null
    . ([scriptblock]::Create($Core.ToString()))
    Invoke-Accion $Accion
    return
}

#incluir interfaz/ventana.ps1
#incluir interfaz/temas.ps1
#incluir interfaz/overlay.ps1
#incluir interfaz/bandeja.ps1
#incluir interfaz/instalador.ps1
#incluir interfaz/menu.ps1
# ================================
# LOGO (paloma, JPEG en base64)
# ================================
#incluir-logo ../assets/logo.jpg
