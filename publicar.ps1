# ================================
#  Publicar versión nueva del Optimizador
# ================================
# 1) Subí $Version en Optimizador.bat (ej. '3.4')
# 2) powershell -ExecutionPolicy Bypass -File publicar.ps1 "Arreglé tal cosa" "Agregué tal otra"
# 3) git add Optimizador.bat version.json ; git commit ; git push
# (para repartir a gente nueva: build.ps1 regenera Optimizador.exe con este .bat adentro)
# Genera version.json con la versión y la huella SHA256 del .bat tal cual está en disco.
# Si el .bat cambia después de correr esto, la huella no coincide y los clientes descartan la descarga.

# cada texto entre comillas es una novedad (sin esto solo tomaba la primera)
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Notas = @())

$bat = Join-Path $PSScriptRoot 'Optimizador.bat'
$json = Join-Path $PSScriptRoot 'version.json'

$m = [regex]::Match(((Get-Content -LiteralPath $bat -TotalCount 40 -Encoding UTF8) -join "`n"), "\`$Version = '([\d.]+)'")
if (-not $m.Success) { Write-Host "No encontré la línea `$Version = '...' en Optimizador.bat" -ForegroundColor Red; exit 1 }
$ver = $m.Groups[1].Value

# la versión publicada tiene que subir, si no nadie recibe el aviso
if (Test-Path -LiteralPath $json) {
    $ant = (Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json).version
    if ($ant -and [version]$ver -lt [version]$ant) {
        Write-Host "version.json ya tiene la v$ant. Subí `$Version en Optimizador.bat antes de publicar." -ForegroundColor Red; exit 1
    }
    # misma versión: sirve para rehacer la huella antes del push; si ya estaba subida, nadie recibe el aviso
    if ($ant -and [version]$ver -eq [version]$ant) { Write-Host "Ojo: misma versión que la publicada (v$ant). Si ya la subiste, subí `$Version." -ForegroundColor Yellow }
}

# git no tiene que tocar los saltos de línea del .bat: cambia la huella y cmd necesita CRLF
if ((Get-Content -LiteralPath $bat -Raw -Encoding UTF8) -match "[^`r]`n") {
    Write-Host 'Optimizador.bat tiene saltos de línea LF sueltos: el lanzador .bat necesita CRLF.' -ForegroundColor Red; exit 1
}

$datos = [ordered]@{
    version = $ver
    sha256  = (Get-FileHash -LiteralPath $bat -Algorithm SHA256).Hash
    notas   = @($Notas)
}
# sin BOM: ConvertFrom-Json del cliente lo lee igual, pero GitHub lo muestra más limpio
[IO.File]::WriteAllText($json, ($datos | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))

Write-Host "version.json listo: v$ver  $($datos.sha256)" -ForegroundColor Green
Write-Host "Ahora: git add Optimizador.bat version.json ; git commit -m `"v$ver`" ; git push"
