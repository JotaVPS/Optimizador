# Optimizador J.vps

Optimizador de Windows para jugar: limpieza de temporales y cachés, modo juego, red (menos picos y cortes), diagnóstico, reparación (DISM + SFC) y datos en pantalla.

## Descarga

Bajá `Optimizador.exe` de [Releases](https://github.com/JotaVPS/Optimizador/releases/latest) y abrilo. La primera vez pide permisos de administrador; si elegís **Instalar**, después abre sin pedirlos.

El programa se fija si hay versión nueva, avisa arriba a la derecha y se actualiza solo mostrando el progreso.

## Estructura

```
Optimizador.bat     el programa (PowerShell + WPF); también abre directo con doble clic
version.json        versión publicada + huella SHA256 del .bat (de acá leen las actualizaciones)
lanzador/           fuente de Optimizador.exe: corre el .bat adentro suyo, sin consolas
herramientas/
  build.ps1         compila dist/Optimizador.exe con el compilador de C# que trae Windows
  publicar.ps1      genera version.json para una versión nueva
dist/               (local) el .exe compilado; se sube como Release
archivo/            (local) versiones viejas y respaldos
```

`Optimizador.bat` y `version.json` tienen que quedar en la raíz: las copias ya instaladas los buscan en esa ruta.

## Publicar una versión

1. Subir `$Version` en `Optimizador.bat`.
2. `powershell -File herramientas\publicar.ps1 "Novedad 1" "Novedad 2"`
3. `powershell -File herramientas\build.ps1`
4. Commit + push de `Optimizador.bat` y `version.json`, y subir `dist\Optimizador.exe` a un Release nuevo.
