# Optimizador J.vps

Optimizador de Windows para jugar: limpieza de temporales y cachés, modo juego, red (menos picos y cortes), diagnóstico, reparación (DISM + SFC) y datos en pantalla.

## Descarga

Bajá `Optimizador.exe` de [Releases](https://github.com/JotaVPS/Optimizador/releases/latest) y abrilo. La primera vez pide permisos de administrador; si elegís **Instalar**, después abre sin pedirlos.

El programa se fija si hay versión nueva, avisa arriba a la derecha y se actualiza solo mostrando el progreso.

## Estructura

```
Optimizador/
├── src/                        código fuente
│   ├── Optimizador.ps1         punto de entrada: parámetros, $Version y el orden de los módulos
│   ├── sistema/                instancia única, instalación, actualizaciones, permisos
│   ├── nucleo/                 lo que corre en segundo plano
│   │   ├── core.ps1            arma el núcleo y reparte las acciones
│   │   ├── acciones/           limpieza, juego, diagnóstico, reparar, red, router...
│   │   ├── nativo.ps1          C# embebido (consola sin ventana, router)
│   │   ├── inicio-windows.ps1  programas que arrancan con Windows
│   │   └── espacio.ps1         analizador de disco
│   ├── interfaz/               ventana, temas, overlay, bandeja, menú
│   └── lanzador/               fuente de Optimizador.exe (C#)
├── assets/                     logo y el LEEME.txt que va en la carpeta para compartir
├── scripts/
│   ├── compilar.cmd            doble clic = build.ps1
│   ├── build.ps1               arma Optimizador.bat, compila dist/Optimizador.exe y la carpeta para compartir
│   └── publicar.ps1            build + version.json para una versión nueva
├── Optimizador.bat             generado por build.ps1 (no editar a mano)
├── version.json                versión publicada + huella SHA256 del .bat
├── CHANGELOG.md                novedades de cada versión
└── dist/                       (local) el .exe compilado; se sube como Release
```

`Optimizador.bat` y `version.json` tienen que quedar en la raíz: las copias ya instaladas los buscan en esa ruta.

## Cómo se arma

Los módulos de `src/` se juntan en un solo archivo: cada línea `#incluir ruta.ps1` se reemplaza por ese archivo, y `#incluir-logo` mete el logo en base64. El resultado es `Optimizador.bat`, un archivo único que abre con doble clic y que va adentro del `.exe`.

```powershell
scripts\compilar.cmd                          # doble clic: .bat + .exe + carpeta del Escritorio
powershell -File scripts\build.ps1            # lo mismo desde la consola
powershell -File scripts\build.ps1 -SoloBat   # solo el .bat, para probar rápido
```

Además actualiza la carpeta `Optimizador J.vps vX` del Escritorio (la que se comparte): la renombra a la versión nueva y le pone el `.exe` y el `LEEME.txt` (sale de `assets/LEEME.txt`).

Los cambios se hacen en `src/`. Si editás `Optimizador.bat` a mano, el próximo build los pisa.

## Publicar una versión

1. Subir `$Version` en `src/Optimizador.ps1` y anotar la novedad en `CHANGELOG.md`.
2. `powershell -File scripts\publicar.ps1 "Novedad 1" "Novedad 2"` (compila todo y genera `version.json`).
3. Commit + push, y subir `dist\Optimizador.exe` a un Release nuevo.
