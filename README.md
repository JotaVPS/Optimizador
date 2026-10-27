# Optimizador J.vps

Optimizador de Windows para jugar: limpieza de temporales y cachés, modo juego, diagnóstico, reparación (DISM + SFC) y datos en pantalla.

## Descarga

Bajá `Optimizador.exe` de [Releases](https://github.com/JotaVPS/Optimizador/releases/latest) y abrilo. La primera vez pide permisos de administrador; si elegís **Instalar**, después abre sin pedirlos.

El programa se fija una vez por día si hay versión nueva y ofrece actualizarse solo.

## Archivos

| Archivo | Qué es |
|---|---|
| `Optimizador.bat` | El programa (PowerShell + WPF). También se puede abrir directo con doble clic. |
| `version.json` | Versión publicada y huella SHA256 del `.bat`; de acá lee las actualizaciones. |
| `lanzador/` | Fuente de `Optimizador.exe`: corre el `.bat` adentro suyo, sin consolas. |
| `build.ps1` | Compila `Optimizador.exe` (usa el compilador de C# que trae Windows). |
| `publicar.ps1` | Genera `version.json` para una versión nueva. |

## Publicar una versión

1. Subir `$Version` en `Optimizador.bat`.
2. `powershell -File publicar.ps1 "Novedad 1" "Novedad 2"`
3. `powershell -File build.ps1` (para el `.exe` de Releases)
4. Commit + push de `Optimizador.bat` y `version.json`, y subir el `.exe` a un Release nuevo.
