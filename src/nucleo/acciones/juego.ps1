    # ---------- MODO JUEGO ----------
    # Programas de fondo que no hacen falta para jugar. Steam, Discord, navegadores y anticheats no se tocan.
    $Fondo = @(
        @{ Nombre = 'OneDrive';        Procesos = 'OneDrive' }
        @{ Nombre = 'Widgets';         Procesos = 'Widgets', 'WidgetService' }
        @{ Nombre = 'Epic Games';      Procesos = 'EpicGamesLauncher', 'EpicWebHelper' }
        @{ Nombre = 'EA App';          Procesos = 'EADesktop', 'EABackgroundService' }
        @{ Nombre = 'BlueStacks';      Procesos = 'HD-Player', 'BlueStacksServices', 'HD-MultiInstanceManager' }
        @{ Nombre = 'Adobe (CCX)';     Procesos = 'CCXProcess', 'CoreSync', 'Adobe Desktop Service' }
        @{ Nombre = 'Autodesk Access'; Procesos = 'AdskAccessCore', 'AdskAccessUIHost' }
        @{ Nombre = 'Gaijin';          Procesos = 'gaijin.net.updater', 'gjagent' }
        @{ Nombre = 'uTorrent Web';    Procesos = 'utweb' }
    )

    # Discord no se cierra (se usa para hablar jugando): se le devuelve a Windows la RAM que tiene reservada
    # sin usar. Solo si la RAM está justa (menos de 20% libre): con RAM de sobra no gana nada y, compartiendo
    # pantalla, recuperar la memoria de golpe puede dar un tironcito en el stream. Una sola vez al entrar al
    # juego. La prioridad no se baja a propósito: con el juego usando todo el procesador, el audio se cortaría.
    # Devuelve los MB liberados, 'sobra' si no hizo falta, o $null si Discord no está abierto.
    function Liberar-RamDiscord {
        $ps = @(Get-Process -Name Discord, DiscordPTB, DiscordCanary -ErrorAction SilentlyContinue)
        if (-not $ps) { return $null }
        $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize
        if ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize -ge 0.2) { return 'sobra' }
        if (-not ('JVps.Memoria' -as [type])) {
            Add-Type -Namespace JVps -Name Memoria -MemberDefinition '[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr proceso);'
        }
        $antes = ($ps | Measure-Object WorkingSet64 -Sum).Sum
        foreach ($p in $ps) { try { [void][JVps.Memoria]::EmptyWorkingSet($p.Handle) } catch { } }
        Start-Sleep -Milliseconds 500
        $despues = (@(Get-Process -Id $ps.Id -ErrorAction SilentlyContinue) | Measure-Object WorkingSet64 -Sum).Sum
        [math]::Max(0, [math]::Round(($antes - $despues) / 1MB))
    }

    function Hacer-ModoJuego {
        Out-Line 'MODO JUEGO' 'title'
        Set-Prog 10 'Buscando programas de fondo'
        $ramAntes = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
        $cerrados = @(); $i = 0
        foreach ($f in $Fondo) {
            $i++
            Set-Prog (10 + [math]::Floor($i * 80 / $Fondo.Count)) $f.Nombre
            $ps = Get-Process -Name $f.Procesos
            if ($ps) {
                $mb = [math]::Round(($ps | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
                $ps | Stop-Process -Force
                $cerrados += $f.Nombre
                Out-Line ("  Cerrado {0,-22}{1,8} MB" -f $f.Nombre, $mb) 'ok'
            }
        }
        if (-not $cerrados) { Out-Line '  No había nada de fondo para cerrar.' 'ok' }
        Set-Prog 92 'Discord'
        $mb = Liberar-RamDiscord
        if ('sobra' -eq $mb) { Out-Line '  Discord: no hace falta liberarle RAM (te sobra memoria), queda como está' 'dim' }
        elseif ($null -ne $mb) { Out-Line ("  Discord: {0:N0} MB de RAM liberados (sigue abierto, la llamada no se corta)" -f $mb) 'ok' }
        Set-Prog 95 'Midiendo RAM'
        Start-Sleep -Seconds 2
        $ramDespues = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
        Out-Line ''
        Out-Line ("RAM libre: {0} GB  ->  {1} GB" -f $ramAntes, $ramDespues) 'title'
        Out-Line 'Se vuelven a abrir solos la próxima vez que prendas la PC.' 'dim'
        Log-Archivo ("Modo juego: cerrados {0}" -f ($cerrados -join ', '))
    }

    # ---------- AJUSTES PARA JUGAR (parte de "Todo para jugar") ----------
    # Plan de energía en Alto rendimiento y la Game Bar sin grabar de fondo. Lo de antes queda en
    # juego_respaldo.json (una sola vez) y vuelve al cerrar la app o con "Restaurar ajustes".
    $ClaveDVR = 'HKCU:\System\GameConfigStore'
    $ClaveCaptura = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
    function Get-PlanActivo { if (([JVps.Consola]::Correr('powercfg', '/getactivescheme')) -join ' ' -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})') { $Matches[1].ToLower() } }

    function Hacer-AjustesJuego {
        Out-Line 'AJUSTES PARA JUGAR' 'title'
        Set-Prog 50 'Plan de energía y Game Bar'
        $resp = Join-Path $Raiz 'juego_respaldo.json'
        $dvr = (Get-ItemProperty $ClaveDVR).GameDVR_Enabled
        $cap = (Get-ItemProperty $ClaveCaptura).AppCaptureEnabled
        $plan = Get-PlanActivo
        if (-not (Test-Path -LiteralPath $resp)) {
            if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
            @{ Plan = $plan; DVR = $dvr; Captura = $cap } | ConvertTo-Json | Set-Content -LiteralPath $resp -Encoding UTF8
        }
        # SCHEME_MIN = Alto rendimiento (el nombre es de Windows: "mínimo ahorro de energía")
        $alto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        if ($plan -eq $alto) { Out-Line ("  {0,-32}{1}" -f 'Plan de energía', 'ya estaba en Alto rendimiento') 'dim' }
        else {
            [void][JVps.Consola]::Correr('powercfg', '/setactive SCHEME_MIN')
            if ((Get-PlanActivo) -eq $alto) { Out-Line ("  {0,-32}{1}" -f 'Plan de energía', 'Alto rendimiento') 'ok' }
            else { Out-Line ("  {0,-32}{1}" -f 'Plan de energía', 'esta PC no tiene Alto rendimiento') 'warn' }
        }
        # la Game Bar graba los últimos minutos todo el tiempo para "guardar clip": eso cuesta FPS
        if ($dvr -eq 0 -and $cap -eq 0) { Out-Line ("  {0,-32}{1}" -f 'Grabación de la Game Bar', 'ya estaba apagada') 'dim' }
        else {
            Set-ItemProperty $ClaveDVR -Name GameDVR_Enabled -Value 0 -Type DWord
            if (-not (Test-Path $ClaveCaptura)) { New-Item -Path $ClaveCaptura -Force | Out-Null }
            Set-ItemProperty $ClaveCaptura -Name AppCaptureEnabled -Value 0 -Type DWord
            Out-Line ("  {0,-32}{1}" -f 'Grabación de la Game Bar', 'apagada') 'ok'
        }
        Out-Line '  Vuelve a como estaba al cerrar el optimizador o con "Restaurar ajustes".' 'dim'
        Log-Archivo 'Ajustes para jugar aplicados'
    }

    # devuelve $true si había algo para volver atrás (también la llama Salir al cerrar la app)
    function Restaurar-Juego {
        $resp = Join-Path $Raiz 'juego_respaldo.json'
        if (-not (Test-Path -LiteralPath $resp)) { return $false }
        $r = Get-Content -LiteralPath $resp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.Plan) { [void][JVps.Consola]::Correr('powercfg', "/setactive $($r.Plan)") }
        if ($null -ne $r.DVR) { Set-ItemProperty $ClaveDVR -Name GameDVR_Enabled -Value ([int]$r.DVR) -Type DWord }
        if ($null -ne $r.Captura) { Set-ItemProperty $ClaveCaptura -Name AppCaptureEnabled -Value ([int]$r.Captura) -Type DWord }
        Remove-Item -LiteralPath $resp -Force
        Log-Archivo 'Ajustes para jugar restaurados'
        $true
    }

    function Hacer-Restaurar {
        Out-Line 'RESTAURAR AJUSTES' 'title'
        if (Restaurar-Juego) { Out-Line '  Plan de energía y Game Bar: como estaban antes de "Todo para jugar".' 'ok' }
        if (Test-Path -LiteralPath $RespaldoRed) { Hacer-RestaurarRed $true }
    }

