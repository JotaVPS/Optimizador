    function Out-Line([string]$texto, [string]$tipo = 'info') {
        if ($sync) { $sync.Q.Enqueue(@{ Tipo = 'line'; T = $texto; K = $tipo }) }
        else {
            $c = @{ info = 'Gray'; ok = 'Green'; warn = 'Yellow'; err = 'Red'; title = 'Cyan'; dim = 'DarkGray' }[$tipo]
            Write-Host $texto -ForegroundColor $c
        }
    }
    function Set-Prog([int]$p, [string]$etiqueta) {
        if ($sync) { $sync.Q.Enqueue(@{ Tipo = 'prog'; P = $p; L = $etiqueta }) }
    }
    function Log-Archivo($texto) {
        $dir = Join-Path $Raiz 'logs'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $f = Join-Path $dir ("optimizador_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
        Add-Content -Path $f -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $texto) -Encoding UTF8
    }
    function TamMB($ruta, $filtro) {
        if (-not (Test-Path -LiteralPath $ruta)) { return 0 }
        # una carpeta que se borra mientras se recorre (TEMP cambia todo el tiempo) corta Get-ChildItem con
        # "no se encuentra el archivo" y tiraba abajo la Revisión completa: se cuenta lo que se llegó a ver
        $total = 0
        try {
            if ($filtro) { Get-ChildItem -LiteralPath $ruta -Filter $filtro -Force -File | ForEach-Object { $total += $_.Length } }
            else { Get-ChildItem -LiteralPath $ruta -Recurse -Force -File | ForEach-Object { $total += $_.Length } }
        } catch { }
        [math]::Round($total / 1MB, 1)
    }

