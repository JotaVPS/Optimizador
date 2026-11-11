@echo off
rem Doble clic: arma Optimizador.bat, compila dist\Optimizador.exe y actualiza la carpeta del Escritorio
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
pause
