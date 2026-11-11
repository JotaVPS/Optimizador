# ================================
#  Compilar el Optimizador
# ================================
# 1) Arma Optimizador.bat juntando los módulos de src\ (cada "#incluir x.ps1" se reemplaza por ese archivo).
# 2) Compila dist\Optimizador.exe con el .bat adentro, la paloma de ícono y la versión del .bat.
#    Usa el compilador de C# que ya trae Windows (.NET Framework 4), no hace falta instalar nada.
#
# 3) Actualiza la carpeta para compartir del Escritorio ("Optimizador J.vps vX": el .exe + LEEME.txt).
#
# Correrlo después de cada cambio en src\:   doble clic en scripts\compilar.cmd
#                                           (o powershell -File scripts\build.ps1)
# Solo el .bat (para probar rápido):         powershell -File scripts\build.ps1 -SoloBat
#
# Optimizador.bat se genera: los cambios van en src\, no en el .bat (se pisan en el próximo build).

param([switch]$SoloBat)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot   # raíz del proyecto (este script vive en scripts\)
$utf8 = New-Object Text.UTF8Encoding $false
$bat = Join-Path $raiz 'Optimizador.bat'

# ---------- 1) Optimizador.bat ----------
# Saltos de línea siempre CRLF (el lanzador .bat no anda con LF) y UTF-8 sin BOM, pase lo que pase con git o el editor.
function Expand-Modulo([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { throw "No existe el módulo $ruta" }
    $dir = Split-Path $ruta
    $sb = New-Object Text.StringBuilder
    foreach ($l in [IO.File]::ReadAllLines($ruta, $utf8)) {
        if ($l -match '^\s*#incluir\s+(\S+)\s*$') {
            $sub = Join-Path $dir $Matches[1]
            [void]$sb.Append((Expand-Modulo $sub))
        } elseif ($l -match '^\s*#incluir-logo\s+(\S+)\s*$') {
            $img = Join-Path $dir $Matches[1]
            [void]$sb.Append('#LOGO:').Append([Convert]::ToBase64String([IO.File]::ReadAllBytes($img))).Append("`r`n")
        } else {
            [void]$sb.Append($l).Append("`r`n")
        }
    }
    $sb.ToString()
}

$texto = Expand-Modulo (Join-Path $raiz 'src\Optimizador.ps1')
$ver = ([regex]::Match($texto, "(?m)^\`$Version = '([\d.]+)'")).Groups[1].Value
if (-not $ver) { throw "No encontré `$Version en src\Optimizador.ps1" }
[IO.File]::WriteAllText($bat, $texto, $utf8)
$hash = (Get-FileHash -LiteralPath $bat -Algorithm SHA256).Hash
Write-Host "Optimizador.bat v$ver listo  ($hash)" -ForegroundColor Green
if ($SoloBat) { return }

# ---------- 2) dist\Optimizador.exe ----------
Add-Type -AssemblyName System.Drawing
$lanz = Join-Path $raiz 'src\lanzador'
$obj = Join-Path $env:TEMP 'optimizador_build'   # intermedios (ícono, versión) fuera del proyecto
$exe = Join-Path $raiz 'dist\Optimizador.exe'
New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
New-Item -ItemType Directory -Force $obj | Out-Null
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'

# ícono: la paloma de assets\logo.jpg en varios tamaños (cada uno un PNG adentro del .ico)
$orig = [Drawing.Image]::FromFile((Join-Path $raiz 'assets\logo.jpg'))
$pngs = foreach ($t in 16, 24, 32, 48, 64, 256) {
    $bmp = New-Object Drawing.Bitmap $t, $t
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($orig, 0, 0, $t, $t); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , @($t, $ms.ToArray())
}
$orig.Dispose()
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
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/reference:$sma" "/out:$exe" "/win32icon:$ico" "/win32manifest:$(Join-Path $lanz 'app.manifest')" "/resource:$bat,Optimizador.bat" (Join-Path $lanz 'Lanzador.cs') $info
if ($LASTEXITCODE) { throw 'No compiló' }
Write-Host "Optimizador.exe v$ver listo" -ForegroundColor Green

# ---------- 3) carpeta para compartir en el Escritorio ----------
# La última "Optimizador J.vps vX" se renombra a la versión nueva y se le pone el .exe y el LEEME al día.
$esc = [Environment]::GetFolderPath('Desktop')
$nombre = "Optimizador J.vps v$ver"
$destino = Join-Path $esc $nombre
if (-not (Test-Path -LiteralPath $destino)) {
    $vieja = Get-ChildItem -LiteralPath $esc -Directory -Filter 'Optimizador J.vps v*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    try { if ($vieja) { Rename-Item -LiteralPath $vieja.FullName -NewName $nombre -ErrorAction Stop } }
    catch { Write-Host "No pude renombrar '$($vieja.Name)' (¿algo abierto adentro?): creo una carpeta nueva" -ForegroundColor Yellow }
    if (-not (Test-Path -LiteralPath $destino)) { New-Item -ItemType Directory -Path $destino | Out-Null }
}
Copy-Item -LiteralPath $exe -Destination $destino -Force
$leeme = ([IO.File]::ReadAllText((Join-Path $raiz 'assets\LEEME.txt'), $utf8)).Replace('{VERSION}', $ver)
[IO.File]::WriteAllText((Join-Path $destino 'LEEME.txt'), $leeme, (New-Object Text.UTF8Encoding $true))
Write-Host "Para compartir: $destino" -ForegroundColor Green
