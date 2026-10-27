# ================================
#  Compilar Optimizador.exe
# ================================
# Mete Optimizador.bat adentro del .exe, con la paloma de ícono y la versión del .bat.
# Usa el compilador de C# que ya trae Windows (.NET Framework 4), no hace falta instalar nada.
# Correrlo después de cada cambio al .bat:  powershell -File herramientas\build.ps1
# Deja el resultado en dist\Optimizador.exe (no se sube al repo: va como Release).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dir = Split-Path $PSScriptRoot   # raíz del proyecto (este script vive en herramientas\)
$bat = Join-Path $dir 'Optimizador.bat'
$src = Join-Path $dir 'lanzador'
$obj = Join-Path $env:TEMP 'optimizador_build'   # intermedios (ícono, versión) fuera del proyecto
$exe = Join-Path $dir 'dist\Optimizador.exe'
New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
New-Item -ItemType Directory -Force $obj | Out-Null

$lineas = [IO.File]::ReadAllLines($bat, [Text.Encoding]::UTF8)
$ver = ([regex]::Match(($lineas | Select-Object -First 40) -join "`n", "\`$Version = '([\d.]+)'")).Groups[1].Value
if (-not $ver) { throw "No encontré `$Version en Optimizador.bat" }

# ícono: la paloma del #LOGO en varios tamaños (cada uno un PNG adentro del .ico)
$b64 = ($lineas | Where-Object { $_.StartsWith('#LOGO:') } | Select-Object -First 1).Substring(6).Trim()
$orig = [Drawing.Image]::FromStream((New-Object IO.MemoryStream (, [Convert]::FromBase64String($b64))))
$pngs = foreach ($t in 16, 24, 32, 48, 64, 256) {
    $bmp = New-Object Drawing.Bitmap $t, $t
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($orig, 0, 0, $t, $t); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , @($t, $ms.ToArray())
}
$ico = Join-Path $obj 'paloma.ico'
$w = New-Object IO.BinaryWriter ([IO.File]::Create($ico))
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$pngs.Count)
$off = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
    $lado = if ($p[0] -ge 256) { 0 } else { $p[0] }   # 0 = 256 en el formato .ico
    $w.Write([byte]$lado); $w.Write([byte]$lado); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$p[1].Length); $w.Write([uint32]$off)
    $off += $p[1].Length
}
foreach ($p in $pngs) { $w.Write($p[1]) }
$w.Close()

# lo que muestra Windows en Propiedades > Detalles y en el aviso de permisos
$info = Join-Path $obj 'Info.cs'
@"
using System.Reflection;
[assembly: AssemblyTitle("Optimizador J.vps")]
[assembly: AssemblyDescription("Optimizador J.vps")]
[assembly: AssemblyProduct("Optimizador J.vps")]
[assembly: AssemblyCompany("J.vps")]
[assembly: AssemblyCopyright("J.vps")]
[assembly: AssemblyVersion("$ver.0.0")]
[assembly: AssemblyFileVersion("$ver.0.0")]
"@ | Set-Content -LiteralPath $info -Encoding UTF8

# si el .exe anterior está abierto Windows no deja pisarlo, pero sí renombrarlo: se corre a .viejo
Get-ChildItem (Split-Path $exe) -Filter '*.viejo' | Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $exe) {
    try { Remove-Item -LiteralPath $exe -Force -ErrorAction Stop }
    catch { Rename-Item -LiteralPath $exe -NewName ("Optimizador.{0:yyyyMMddHHmmss}.viejo" -f (Get-Date)) }
}

# el PowerShell 5.1 que trae Windows, como librería: el .exe corre el script adentro suyo
$sma = [PSObject].Assembly.Location
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/reference:$sma" "/out:$exe" "/win32icon:$ico" "/win32manifest:$(Join-Path $src 'app.manifest')" "/resource:$bat,Optimizador.bat" (Join-Path $src 'Lanzador.cs') $info
if ($LASTEXITCODE) { throw 'No compiló' }
Write-Host "Optimizador.exe v$ver listo" -ForegroundColor Green
