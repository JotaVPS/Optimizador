    # ---------- RED ----------
    # Solo cambios que se deshacen: antes de tocar nada guarda cómo estaba todo en red_respaldo.json
    # (una sola vez, así "Restaurar ajustes" siempre vuelve a lo original). No cambia DNS ni IP y no hace
    # reset de winsock/TCP (eso sí puede dejar sin internet hasta reiniciar).
    $RespaldoRed = Join-Path $Raiz 'red_respaldo.json'
    # ahorro de energía de la placa (Ethernet y Wi-Fi): mete microcortes y picos; apagarlo no baja la velocidad.
    # Se buscan por la clave del driver (no por el nombre, que cambia con el idioma) y solo si aceptan "0".
    $AhorroPlaca = '*EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'PowerSavingMode', 'GigaLite', '*PMARPOffload', '*PMNSOffload'
    $SubWifi = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; $SetWifi = '12bbebe6-58d6-4636-95bb-3217ef867c1a'   # plan de energía > adaptador inalámbrico
    $ClaveDO = 'Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings'
    $ClaveMM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

    function Get-PlacaActiva {
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $r) { return $null }
        $a = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex
        if ($a) { $a | Add-Member -NotePropertyName Gateway -NotePropertyValue $r.NextHop -PassThru }
    }
    function Medir-Ping($destino, $n = 20) {
        $ping = New-Object Net.NetworkInformation.Ping
        $t = @(); $perd = 0
        for ($i = 0; $i -lt $n; $i++) {
            try { $r = $ping.Send($destino, 1000); if ($r.Status -eq 'Success') { $t += [int]$r.RoundtripTime } else { $perd++ } } catch { $perd++ }
            Start-Sleep -Milliseconds 120
        }
        if (-not $t) { return $null }
        # jitter: cuánto salta de un ping al siguiente (lo que se siente como tirones en el juego)
        $jit = if ($t.Count -gt 1) { (@(for ($i = 1; $i -lt $t.Count; $i++) { [math]::Abs($t[$i] - $t[$i - 1]) }) | Measure-Object -Average).Average } else { 0 }
        [pscustomobject]@{ Prom = ($t | Measure-Object -Average).Average; Max = ($t | Measure-Object -Maximum).Maximum; Jitter = $jit; Perdidos = $perd; N = $n }
    }
    function Out-Ping($nombre, $m) {
        if (-not $m) { Out-Line ("  {0,-10} sin respuesta" -f $nombre) 'err'; return }
        $k = if ($m.Perdidos -or $m.Jitter -gt 15 -or $m.Max -gt 150) { 'warn' } else { 'ok' }
        Out-Line ("  {0,-10} {1,4:N0} ms   máx {2,4} ms   jitter {3,4:N1} ms   perdidos {4}/{5}" -f $nombre, $m.Prom, $m.Max, $m.Jitter, $m.Perdidos, $m.N) $k
    }
    function Get-WifiPlan {
        $q = ([JVps.Consola]::Correr('powercfg', "/q SCHEME_CURRENT $SubWifi $SetWifi")) -join "`n"
        $v = [regex]::Matches($q, ':\s*0x([0-9a-fA-F]{8})')
        if ($v.Count -ge 2) { @{ AC = [Convert]::ToInt32($v[0].Groups[1].Value, 16); DC = [Convert]::ToInt32($v[1].Groups[1].Value, 16) } }
    }
    function Esperar-Red($gateway, $segundos = 30) {
        # después de reiniciar la placa la conexión tarda unos segundos en volver
        $ping = New-Object Net.NetworkInformation.Ping
        $hasta = (Get-Date).AddSeconds($segundos)
        while ((Get-Date) -lt $hasta) {
            try { if ($ping.Send($gateway, 1000).Status -eq 'Success') { return $true } } catch { }
            Start-Sleep -Seconds 1
        }
        $false
    }

    function Diagnostico-Red($placa) {
        Out-Line ("  Conexión: {0} ({1})" -f $placa.Name, $placa.InterfaceDescription) 'dim'
        if ($placa.PhysicalMediaType -match '802\.11|Wireless' -or $placa.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11') {
            $w = ([JVps.Consola]::Correr('netsh', 'wlan show interfaces')) -join "`n"
            $senal = if ($w -match '(\d+)\s*%') { [int]$Matches[1] } else { $null }
            $banda = if ($w -match '(\d(?:[\.,]\d)?)\s*GHz') { $Matches[1] -replace ',', '.' } else { $null }
            if ($senal -ne $null) { Out-Line ("  Wi-Fi: señal {0}%{1}" -f $senal, $(if ($banda) { "  ·  banda $banda GHz" } else { '' })) $(if ($senal -lt 60) { 'warn' } else { 'ok' }) }
            if ($senal -ne $null -and $senal -lt 60) { Out-Line '    Señal baja: acercate al router o sacá obstáculos (paredes, el gabinete tapando la antena).' 'warn' }
            if ($banda -eq '2.4') { Out-Line '    Estás en 2.4 GHz: si el router tiene red de 5 GHz, conectate a esa (menos interferencia y menos ping).' 'warn' }
            Out-Line '    Para jugar, un cable siempre gana: el Wi-Fi tiene picos que ningún ajuste saca del todo.' 'dim'
        } else {
            # placa Gigabit conectada a 100 Mbps: casi siempre el cable (viejo o dañado) o el puerto del router
            $mbps = [math]::Round($placa.ReceiveLinkSpeed / 1e6)
            $giga = (Get-NetAdapterAdvancedProperty -Name $placa.Name -RegistryKeyword '*SpeedDuplex').ValidRegistryValues -contains '6'
            if ($giga -and $mbps -lt 1000) {
                Out-Line ("  Cable: conectado a {0} Mbps, pero la placa da 1000 Mbps" -f $mbps) 'warn'
                Out-Line '    Probá otro cable (Cat5e o Cat6) u otro puerto del router. Si tu plan es de más de 100 megas, lo estás perdiendo ahí.' 'warn'
            } else { Out-Line ("  Cable: conectado a {0} Mbps" -f $mbps) 'ok' }
        }
        Set-Prog 25 'Midiendo latencia al router'
        $mr = Medir-Ping $placa.Gateway
        Out-Ping 'Router' $mr
        Set-Prog 45 'Midiendo latencia a internet'
        $mi = Medir-Ping '1.1.1.1'
        Out-Ping 'Internet' $mi
        if ($mr -and ($mr.Perdidos -or $mr.Jitter -gt 5 -or $mr.Max -gt 30)) {
            Out-Line '    Hay saltos ya dentro de tu casa (PC → router): el problema es el Wi-Fi o el cable, no el proveedor.' 'warn'
        } elseif ($mi -and ($mi.Perdidos -or $mi.Jitter -gt 15 -or $mi.Max -gt 150)) {
            Out-Line '    Hasta el router anda bien; los picos aparecen afuera. Suele ser alguien descargando en la casa' 'warn'
            Out-Line '    (si el router tiene QoS o "SQM", activalo) o el proveedor en horario pico.' 'warn'
        }
        $mi
    }

    function Hacer-Red {
        Out-Line 'RED' 'title'
        Set-Prog 5 'Buscando la conexión'
        $placa = Get-PlacaActiva
        if (-not $placa) { Out-Line '  No hay conexión a internet activa.' 'err'; return }
        $antes = Diagnostico-Red $placa
        if (-not $EsAdmin) { Out-Line ''; Out-Line '  Para aplicar los ajustes hacen falta permisos de administrador.' 'warn'; return }

        Out-Line ''
        Out-Line 'AJUSTES' 'title'
        Crear-PuntoRestauracion 'ajustes de Red' 50
        Set-Prog 55 'Guardando cómo está todo'
        $guid = $placa.InterfaceGuid
        $claveIf = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        $props = @(Get-NetAdapterAdvancedProperty -Name $placa.Name -AllProperties | Where-Object { $AhorroPlaca -contains $_.RegistryKeyword -and $_.ValidRegistryValues -contains '0' })
        if (-not (Test-Path -LiteralPath $RespaldoRed)) {
            $mm = Get-ItemProperty $ClaveMM
            $resp = [ordered]@{
                Fecha = (Get-Date).ToString('s'); Placa = $placa.Name; Guid = $guid
                AutoTuning = [string](Get-NetTCPSetting -SettingName Internet).AutoTuningLevelLocal
                Throttling = $mm.NetworkThrottlingIndex; Responsiveness = $mm.SystemResponsiveness
                DO = (Get-ItemProperty $ClaveDO).DownloadMode
                AckFreq = (Get-ItemProperty $claveIf).TcpAckFrequency; NoDelay = (Get-ItemProperty $claveIf).TCPNoDelay
                Props = @($props | ForEach-Object { @{ K = $_.RegistryKeyword; V = [string]$_.RegistryValue[0] } })
                Wifi = Get-WifiPlan
            }
            if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
            $resp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $RespaldoRed -Encoding UTF8
            Out-Line '  Respaldo guardado: "Restaurar ajustes" lo deja todo como estaba.' 'dim'
        }

        Set-Prog 65 'Aplicando'
        # autoajuste de TCP: algunos "optimizadores" lo apagan y eso limita la velocidad de descarga
        if ((Get-NetTCPSetting -SettingName Internet).AutoTuningLevelLocal -ne 'Normal') {
            [void][JVps.Consola]::Correr('netsh', 'int tcp set global autotuninglevel=normal')
            Out-Line ("  {0,-44}{1}" -f 'Autoajuste de TCP', 'normal (estaba limitado)') 'ok'
        } else { Out-Line ("  {0,-44}{1}" -f 'Autoajuste de TCP', 'ya estaba bien') 'dim' }
        # que Windows no frene el tráfico de red mientras corre audio/video (juego + Discord)
        Set-ItemProperty $ClaveMM -Name NetworkThrottlingIndex -Value ([int]-1) -Type DWord
        Set-ItemProperty $ClaveMM -Name SystemResponsiveness -Value 10 -Type DWord
        Out-Line ("  {0,-44}{1}" -f 'Límite de red con multimedia', 'sacado') 'ok'
        # Windows Update no sube actualizaciones a PCs de desconocidos por internet (solo red local)
        if (-not (Test-Path $ClaveDO)) { New-Item -Path $ClaveDO -Force | Out-Null }
        Set-ItemProperty $ClaveDO -Name DownloadMode -Value 1 -Type DWord
        Out-Line ("  {0,-44}{1}" -f 'Windows Update subiendo a otras PCs', 'solo red local') 'ok'
        # paquetes chicos sin demora (Nagle): ayuda en juegos que van por TCP
        Set-ItemProperty $claveIf -Name TcpAckFrequency -Value 1 -Type DWord
        Set-ItemProperty $claveIf -Name TCPNoDelay -Value 1 -Type DWord
        Out-Line ("  {0,-44}{1}" -f 'Envío de paquetes chicos sin demora', 'activado') 'ok'
        $wifi = Get-WifiPlan
        if ($wifi -and $wifi.AC -ne 0) {
            [void][JVps.Consola]::Correr('powercfg', "/setacvalueindex SCHEME_CURRENT $SubWifi $SetWifi 0")
            [void][JVps.Consola]::Correr('powercfg', '/setactive SCHEME_CURRENT')
            Out-Line ("  {0,-44}{1}" -f 'Wi-Fi enchufado', 'rendimiento máximo') 'ok'
        }
        [void][JVps.Consola]::Correr('ipconfig', '/flushdns')
        [void][JVps.Consola]::Correr('netsh', 'interface ip delete arpcache')
        Out-Line ("  {0,-44}{1}" -f 'Cachés de DNS y ARP', 'vaciadas') 'ok'

        $cambiar = @($props | Where-Object { [string]$_.RegistryValue[0] -ne '0' })
        if ($cambiar) {
            Set-Prog 75 'Placa de red: sacando el ahorro de energía'
            Out-Line ("  {0,-44}{1}" -f 'Ahorro de energía de la placa', "apagado ($($cambiar.Count))") 'ok'
            foreach ($p in $cambiar) { Set-NetAdapterAdvancedProperty -Name $placa.Name -RegistryKeyword $p.RegistryKeyword -RegistryValue '0' -NoRestart }
        }
        # reinicio de la placa: aplica Nagle y el ahorro de energía; si la conexión no vuelve, se deshace todo
        Out-Line '  Se reinicia la placa de red: la conexión se corta unos segundos.' 'warn'
        Set-Prog 80 'Reiniciando la placa de red'
        Restart-NetAdapter -Name $placa.Name -Confirm:$false
        Set-Prog 82 'Esperando que vuelva la conexión'
        if (-not (Esperar-Red $placa.Gateway)) {
            Out-Line '  La conexión no volvió: deshaciendo los cambios.' 'err'
            Hacer-RestaurarRed $true
            return
        }
        Start-Sleep -Seconds 3   # la placa recién levantada da pings altos los primeros segundos

        Out-Line ''
        Out-Line 'DESPUÉS' 'title'
        Set-Prog 90 'Midiendo de nuevo'
        $despues = Medir-Ping '1.1.1.1'
        Out-Ping 'Internet' $despues
        if ($antes -and $despues) {
            Out-Line ''
            Out-Line ("Internet: {0:N0} ms → {1:N0} ms   ·   jitter {2:N1} → {3:N1} ms" -f $antes.Prom, $despues.Prom, $antes.Jitter, $despues.Jitter) 'title'
        }
        Out-Line 'El ping a internet depende sobre todo del proveedor: los ajustes sacan los cortes y picos de tu lado.' 'dim'
        Log-Archivo ("Red: ajustes aplicados en {0}" -f $placa.Name)
    }

    function Hacer-RestaurarRed([bool]$automatico = $false) {
        if (-not $automatico) { Out-Line 'RESTAURAR RED' 'title' }
        if (-not $EsAdmin) { Out-Line '  Necesita permisos de administrador.' 'err'; return }
        if (-not (Test-Path -LiteralPath $RespaldoRed)) { Out-Line '  No hay nada para restaurar: los ajustes de red nunca se aplicaron.' 'ok'; return }
        Set-Prog 30 'Volviendo todo a como estaba'
        $r = Get-Content -LiteralPath $RespaldoRed -Raw -Encoding UTF8 | ConvertFrom-Json
        $claveIf = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($r.Guid)"
        $nivel = @{ Normal = 'normal'; Disabled = 'disabled'; Restricted = 'restricted'; HighlyRestricted = 'highlyrestricted'; Experimental = 'experimental' }[$r.AutoTuning]
        if ($nivel) { [void][JVps.Consola]::Correr('netsh', "int tcp set global autotuninglevel=$nivel") }
        # valor que no existía antes: se borra en vez de dejarlo en otro número
        function Volver($clave, $nombre, $valor) {
            if ($null -eq $valor) { Remove-ItemProperty -Path $clave -Name $nombre }
            else { Set-ItemProperty -Path $clave -Name $nombre -Value ([int]$valor) -Type DWord }
        }
        Volver $ClaveMM 'NetworkThrottlingIndex' $r.Throttling
        Volver $ClaveMM 'SystemResponsiveness' $r.Responsiveness
        Volver $ClaveDO 'DownloadMode' $r.DO
        Volver $claveIf 'TcpAckFrequency' $r.AckFreq
        Volver $claveIf 'TCPNoDelay' $r.NoDelay
        if ($r.Wifi) {
            [void][JVps.Consola]::Correr('powercfg', "/setacvalueindex SCHEME_CURRENT $SubWifi $SetWifi $($r.Wifi.AC)")
            [void][JVps.Consola]::Correr('powercfg', '/setactive SCHEME_CURRENT')
        }
        foreach ($p in $r.Props) { Set-NetAdapterAdvancedProperty -Name $r.Placa -RegistryKeyword $p.K -RegistryValue $p.V -NoRestart }
        Set-Prog 60 'Reiniciando la placa de red'
        Restart-NetAdapter -Name $r.Placa -Confirm:$false
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1).NextHop
        Set-Prog 80 'Esperando que vuelva la conexión'
        $volvio = if ($gw) { Esperar-Red $gw } else { Start-Sleep -Seconds 10; $true }
        Remove-Item -LiteralPath $RespaldoRed -Force
        Out-Line '  Red restaurada: todo quedó como estaba antes de los ajustes.' 'ok'
        if (-not $volvio) { Out-Line '  La conexión todavía no volvió: esperá unos segundos o desconectá y conectá el cable / Wi-Fi.' 'warn' }
        Log-Archivo 'Red: restaurada'
    }

