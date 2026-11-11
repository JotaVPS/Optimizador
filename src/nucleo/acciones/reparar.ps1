    # ---------- REPARAR ----------
    function Hacer-Reparar {
        Out-Line 'REPARAR WINDOWS' 'title'
        if (-not $EsAdmin) { Out-Line '  Necesita permisos de administrador. Abrilo desde Optimizador.bat y aceptá el aviso.' 'err'; return }
        Out-Line '  Tarda entre 10 y 30 minutos. No apagues la PC.' 'warn'
        Crear-PuntoRestauracion 'Reparar Windows'
        Set-Prog 5 'DISM: reparando la imagen de Windows'
        $pr = [JVps.Consola]::Abrir('DISM', '/Online /Cleanup-Image /RestoreHealth')
        while ($null -ne ($l = $pr.StandardOutput.ReadLine())) {
            $t = ($l -replace "`0", '').Trim()
            if ($t -match '(\d+)[\.,]\d+%') { Set-Prog (5 + [int]$Matches[1] / 2) 'DISM: reparando la imagen de Windows' }
            elseif ($t -and $t -notmatch '^\[') { Out-Line "  $t" 'dim' }
        }
        Set-Prog 55 'SFC: revisando archivos del sistema'
        $pr = [JVps.Consola]::Abrir('sfc', '/scannow')
        while ($null -ne ($l = $pr.StandardOutput.ReadLine())) {
            $t = ($l -replace "`0", '').Trim()
            if ($t -match '(\d+)\s*%') { Set-Prog (55 + [int]$Matches[1] * 45 / 100) 'SFC: revisando archivos del sistema' }
            elseif ($t) { Out-Line "  $t" 'dim' }
        }
        Out-Line ''
        Out-Line 'Reparación terminada.' 'title'
        Log-Archivo 'Reparar: DISM + SFC'
    }

