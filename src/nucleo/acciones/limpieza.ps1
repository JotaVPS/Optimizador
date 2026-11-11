    # ---------- LIMPIEZA ----------
    # Solo cosas que Windows o los programas regeneran solos.
    # No se tocan: Papelera, Descargas, Minidump (sirven para diagnosticar pantallazos), cache de shaders (da tirones al rehacerse).
    $Limpiezas = @(
        @{ Nombre = 'Temporales del usuario';      Ruta = $env:TEMP;                                              Admin = $false }
        @{ Nombre = 'Temporales de Windows';       Ruta = "$env:WINDIR\Temp";                                     Admin = $true  }
        @{ Nombre = 'Descargas de Windows Update'; Ruta = "$env:WINDIR\SoftwareDistribution\Download";            Admin = $true  }
        @{ Nombre = 'Reportes de errores';         Ruta = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive";  Admin = $true  }
        @{ Nombre = 'Cola de reportes';            Ruta = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue";    Admin = $true  }
        @{ Nombre = 'Caché de miniaturas';         Ruta = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Filtro = 'thumbcache_*.db'; Admin = $false }
        @{ Nombre = 'Caché de Discord';            Ruta = "$env:APPDATA\discord\Cache";                           Admin = $false }
        @{ Nombre = 'Caché de FiveM';              Ruta = "$env:LOCALAPPDATA\FiveM\FiveM.app\data\cache";         Admin = $false }
        @{ Nombre = 'Logs de Steam';               Ruta = "${env:ProgramFiles(x86)}\Steam\logs";                  Admin = $true  }
    )

    function Hacer-Limpieza {
        Out-Line 'LIMPIEZA' 'title'
        if ($Simular) { Out-Line 'Modo simulación: solo se mide, no se borra nada.' 'warn' }
        $total = 0; $i = 0
        foreach ($l in $Limpiezas) {
            $i++
            Set-Prog ([math]::Floor($i * 100 / $Limpiezas.Count)) $l.Nombre
            if (-not (Test-Path -LiteralPath $l.Ruta)) { continue }
            if ($l.Admin -and -not $EsAdmin) { Out-Line ("  {0,-30}{1,14}" -f $l.Nombre, 'requiere admin') 'warn'; continue }
            $antes = TamMB $l.Ruta $l.Filtro
            if (-not $Simular) {
                # lo que está en uso no se puede borrar: se saltea sin error. Uno por uno y con try: si otro programa
                # borra una carpeta mientras se recorre (TEMP cambia todo el tiempo), Remove-Item -Recurse cortaba
                # toda la limpieza con "no se encuentra el archivo"
                $items = try { if ($l.Filtro) { @(Get-ChildItem -LiteralPath $l.Ruta -Filter $l.Filtro -Force -File) } else { @(Get-ChildItem -LiteralPath $l.Ruta -Force) } } catch { @() }
                foreach ($it in $items) { try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
            }
            $despues = if ($Simular) { 0 } else { TamMB $l.Ruta $l.Filtro }
            $mb = [math]::Max(0.0, [math]::Round($antes - $despues, 1))
            $total += $mb
            Out-Line ("  {0,-30}{1,11:N1} MB" -f $l.Nombre, $mb) 'ok'
        }
        if (-not $Simular) { [void][JVps.Consola]::Correr('ipconfig', '/flushdns'); Out-Line ("  {0,-30}{1,14}" -f 'Caché de DNS', 'vaciada') 'ok' }
        $verbo = if ($Simular) { 'Se liberarían' } else { 'Liberado' }
        Out-Line ''
        Out-Line ("{0}: {1:N0} MB" -f $verbo, $total) 'title'
        Log-Archivo ("Limpieza{0}: {1:N0} MB" -f $(if ($Simular) { ' (simulada)' } else { '' }), $total)
    }

