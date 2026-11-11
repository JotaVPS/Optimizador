    # ---------- DIAGNOSTICO ----------
    # pantallazos azules frecuentes: nombre, qué quiere decir y a qué apunta (ram / driver / gpu / hw)
    $CodigosBSOD = @{
        '0x0000000a' = 'IRQL_NOT_LESS_OR_EQUAL', 'Un driver o la RAM accedió a memoria que no debía.', 'driver'
        '0x0000001a' = 'MEMORY_MANAGEMENT', 'Error manejando la memoria: casi siempre RAM.', 'ram'
        '0x0000001e' = 'KMODE_EXCEPTION_NOT_HANDLED', 'Un driver tiró un error que nadie atajó.', 'driver'
        '0x00000018' = 'REFERENCE_BY_POINTER', 'Un driver liberó algo que todavía se usaba.', 'driver'
        '0x00000019' = 'BAD_POOL_HEADER', 'Memoria del sistema corrupta: driver o RAM.', 'ram'
        '0x0000003b' = 'SYSTEM_SERVICE_EXCEPTION', 'Falló un driver mientras Windows lo llamaba.', 'driver'
        '0x0000004e' = 'PFN_LIST_CORRUPT', 'Tabla de memoria corrupta: casi siempre RAM.', 'ram'
        '0x00000050' = 'PAGE_FAULT_IN_NONPAGED_AREA', 'Se leyó memoria que no existía: RAM o driver.', 'ram'
        '0x0000007e' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED', 'Un driver tiró un error sin manejar.', 'driver'
        '0x0000009f' = 'DRIVER_POWER_STATE_FAILURE', 'Un driver no respondió al suspender o despertar.', 'driver'
        '0x000000be' = 'ATTEMPTED_WRITE_TO_READONLY_MEMORY', 'Se escribió en memoria de solo lectura: driver o RAM.', 'driver'
        '0x000000c5' = 'DRIVER_CORRUPTED_EXPOOL', 'Un driver rompió memoria del sistema.', 'driver'
        '0x000000d1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL', 'Un driver (muchas veces el de red) accedió mal a memoria.', 'driver'
        '0x000000ef' = 'CRITICAL_PROCESS_DIED', 'Murió un proceso esencial de Windows.', 'driver'
        '0x00000116' = 'VIDEO_TDR_FAILURE', 'La placa de video dejó de responder.', 'gpu'
        '0x00000124' = 'WHEA_UNCORRECTABLE_ERROR', 'El procesador reportó un error de hardware: overclock, temperatura o fuente.', 'hw'
        '0x00000133' = 'DPC_WATCHDOG_VIOLATION', 'Un driver (o el SSD) se colgó demasiado tiempo.', 'driver'
        '0x00000139' = 'KERNEL_SECURITY_CHECK_FAILURE', 'Windows detectó datos corruptos: driver o RAM.', 'driver'
    }
    # velocidad para la que está hecha la RAM, sacada del código de modelo (KF3200C16 → 3200, BL8G32C16 → 3200);
    # Windows solo dice a cuánto anda, no a cuánto puede ir
    function Get-RamNominal($mod) {
        $pn = [string]$mod.PartNumber
        if ($pn -match '(?<!\d)(2133|2400|2666|2800|2933|3000|3200|3466|3600|3733|4000|4133|4266|4400|4800|5200|5600|6000|6400|6800|7200|7600|8000)(?!\d)') { return [int]$Matches[1] }
        $corto = @{ '21' = 2133; '24' = 2400; '26' = 2666; '29' = 2933; '30' = 3000; '32' = 3200; '36' = 3600; '40' = 4000; '44' = 4400; '48' = 4800; '52' = 5200; '56' = 5600; '60' = 6000; '64' = 6400 }
        if ($pn -match '[A-Z](\d{2})C\d{2}' -and $corto[$Matches[1]]) { return $corto[$Matches[1]] }
        if ($pn -match 'KF\d(\d{2})C' -and $corto[$Matches[1]]) { return $corto[$Matches[1]] }   # Kingston Fury: KF432C16 → 3200
        if ($mod.Speed -gt $mod.ConfiguredClockSpeed) { return [int]$mod.Speed }
        $null
    }
    # sin XMP la placa pone la RAM en una velocidad estándar JEDEC (2133, 2400, 2666, 3200, 4800...).
    # Si anda por debajo de su velocidad pero en un valor que no es estándar (ej. 3000), la bajó alguien a mano
    # en el BIOS, casi siempre porque a full no era estable: no es algo para corregir.
    function Test-RamAMano([int]$mhz) {
        foreach ($j in 1600, 1866, 2133, 2400, 2666, 2933, 3200, 4800, 5600, 6400) { if ([math]::Abs($mhz - $j) -le 20) { return $false } }
        $true
    }

    function Hacer-Diagnostico {
        Out-Line 'DIAGNÓSTICO' 'title'
        Set-Prog 15 'Memoria RAM'
        $mods = @(Get-CimInstance Win32_PhysicalMemory)
        $totalGB = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
        $mhz = $mods[0].ConfiguredClockSpeed
        Out-Line ("  RAM: {0} GB en {1} módulos a {2} MHz" -f $totalGB, $mods.Count, $mhz) 'ok'
        $nominal = Get-RamNominal $mods[0]
        $hayBsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-7) }).Count
        if ($nominal -and $nominal -gt $mhz + 50 -and (Test-RamAMano $mhz)) {
            Out-Line ("    Es RAM de {0} MHz y está configurada a mano a {1} MHz: se respeta así." -f $nominal, $mhz) 'dim'
        } elseif ($nominal -and $nominal -gt $mhz + 50) {
            Out-Line ("    Es RAM de {0} MHz y está andando a {1} MHz." -f $nominal, $mhz) 'warn'
            if ($hayBsod) { Out-Line '    Si la bajaste a propósito por los pantallazos, dejala así. Si no, revisá el XMP/EXPO en el BIOS.' 'dim' }
            else { Out-Line '    Activá XMP / EXPO / DOCP en el BIOS para que vaya a su velocidad: se nota en los juegos.' 'dim' }
        }

        Set-Prog 35 'Pantallazos y apagones'
        $desde = (Get-Date).AddDays(-7)
        $bsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $desde })
        $apagon = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $desde })
        $k = if ($bsod.Count -or $apagon.Count) { 'err' } else { 'ok' }
        Out-Line ("  Últimos 7 días: {0} pantallazos azules, {1} apagones inesperados" -f $bsod.Count, $apagon.Count) $k
        if ($bsod.Count) {
            # cada código, cuántas veces y qué significa en criollo
            $porCodigo = $bsod | Group-Object { if ($_.Message -match '0x([0-9a-fA-F]{8})') { '0x' + $Matches[1].ToLower() } else { '?' } } | Sort-Object Count -Descending
            Out-Line ("    Último: {0:dd/MM HH:mm}" -f $bsod[0].TimeCreated) 'err'
            $dias = [math]::Floor(((Get-Date) - $bsod[0].TimeCreated).TotalDays)
            if ($dias -ge 3) { Out-Line "    Hace $dias días que no hay pantallazos: si cambiaste algo (RAM, drivers), parece que funcionó." 'ok' }
            foreach ($g in $porCodigo) {
                $c = $g.Name -replace '^0x0*', '0x'
                $q = $CodigosBSOD[$g.Name]
                Out-Line ("    {0,2}×  {1,-6} {2}" -f $g.Count, $c, $(if ($q) { $q[0] } else { 'código poco común' })) 'warn'
                if ($q) { Out-Line ("              {0}" -f $q[1]) 'dim' }
            }
            # conclusión: qué probar primero
            $tipos = @($porCodigo | ForEach-Object { if ($CodigosBSOD[$_.Name]) { $CodigosBSOD[$_.Name][2] } })
            Out-Line '' 'dim'
            if ($porCodigo.Count -ge 3) {
                Out-Line '    Muchos códigos distintos: casi siempre es la RAM inestable (XMP/EXPO) o un driver.' 'warn'
                Out-Line '    Probá en este orden: XMP/EXPO desactivado en el BIOS · "Diagnóstico de memoria de Windows" · drivers de video y chipset al día.' 'dim'
            } elseif ($tipos -contains 'gpu') {
                Out-Line '    Apunta al driver de video: reinstalalo limpio desde la página de NVIDIA/AMD.' 'warn'
            } elseif ($tipos -contains 'hw') {
                Out-Line '    Apunta a hardware: overclock, temperaturas o fuente. Sacá cualquier overclock y mirá las temperaturas.' 'warn'
            } elseif ($tipos -contains 'ram') {
                Out-Line '    Apunta a la RAM: probá con el XMP/EXPO desactivado y pasá el "Diagnóstico de memoria de Windows".' 'warn'
            } else {
                Out-Line '    Apunta a un driver: actualizá video, chipset y red, y desinstalá lo que hayas instalado esos días.' 'warn'
            }
        }

        Set-Prog 55 'Discos'
        # Win32_LogicalDisk y MSFT_PhysicalDisk directos: Get-Volume / Get-PhysicalDisk cargan un módulo que tarda ~10 s
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID | ForEach-Object {
            $libre = [math]::Floor($_.FreeSpace / 1GB); $tot = [math]::Floor($_.Size / 1GB)
            $pct = if ($tot) { [math]::Round($libre * 100 / $tot) } else { 0 }
            $k = if ($pct -lt 10) { 'err' } elseif ($pct -lt 20) { 'warn' } else { 'ok' }
            Out-Line ("  Disco {0}  {1} GB libres de {2} GB ({3}%)" -f $_.DeviceID, $libre, $tot, $pct) $k
        }
        Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk | ForEach-Object {
            $sano = [int]$_.HealthStatus -eq 0   # 0 = sano, 1 = advertencia, 2 = con problemas
            $estado = @{ 1 = 'con advertencias'; 2 = 'con problemas' }[[int]$_.HealthStatus]
            Out-Line ("    {0}: {1}" -f ([string]$_.FriendlyName).Trim(), $(if ($sano) { 'sano' } else { $estado })) $(if ($sano) { 'dim' } else { 'err' })
        }

        Set-Prog 75 'Arranque y energía'
        $inicio = @(Get-ProgramasInicio | Where-Object Activo)
        if ($inicio.Count -gt 12) {
            Out-Line ("  Programas que arrancan con Windows: {0}" -f $inicio.Count) 'warn'
            Out-Line '    Apagá los que no uses en la pestaña Arranque (arriba a la derecha)' 'dim'
        } else { Out-Line ("  Programas que arrancan con Windows: {0}" -f $inicio.Count) 'ok' }
        $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled
        if ($hb -eq 1) { Out-Line '  Inicio rápido: activado (si se cuelga al apagar, desactivalo)' 'warn' }
        else { Out-Line '  Inicio rápido: desactivado' 'ok' }

        $dc = @(Get-Process -Name Discord, DiscordPTB, DiscordCanary -ErrorAction SilentlyContinue)
        if ($dc) {
            Out-Line ("  Discord abierto: {0:N0} MB de RAM" -f (($dc | Measure-Object WorkingSet64 -Sum).Sum / 1MB)) 'ok'
            Out-Line '    Para más FPS: en Discord, Configuración > Superposición del juego > apagada (dibuja encima del juego todo el tiempo).' 'dim'
            Out-Line '    Si la RAM está justa, el Modo juego le libera memoria sin cerrarlo ni cortar la llamada.' 'dim'
        }

        Set-Prog 90 'Placa de video'
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' } | Select-Object -First 1
        if ($gpu) {
            $edad = [math]::Round(((Get-Date) - $gpu.DriverDate).TotalDays)
            Out-Line ("  {0}: driver de hace {1} días" -f $gpu.Name, $edad) $(if ($edad -gt 180) { 'warn' } else { 'ok' })
        }
        Log-Archivo "Diagnóstico: RAM $mhz MHz, $($bsod.Count) BSOD / $($apagon.Count) apagones en 7 días"
    }

    # ---------- PUNTAJE (parte de la Revisión completa) ----------
    # Arranca en 100 y resta por cada cosa a mejorar, según cuánto pesa en el día a día. Cada una dice cómo
    # se arregla y si el Optimizador lo hace solo (Auto: con Todo para jugar) o lo tenés que hacer vos.
    function Hacer-Puntaje {
        Set-Prog 95 'Calculando el puntaje'
        $fallas = New-Object Collections.ArrayList
        function Falla([int]$resta, [string]$que, [string]$arreglo, [bool]$auto = $false) { [void]$fallas.Add(@{ R = $resta; Q = $que; A = $arreglo; Auto = $auto }) }

        $evBsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-7) })
        $bsod = $evBsod.Count
        # si hace 3 días que no hay ninguno, lo que cambiaron (RAM, drivers) probablemente lo arregló: pesa menos
        if ($bsod -and ((Get-Date) - $evBsod[0].TimeCreated).TotalDays -ge 3) { Falla 10 ("$bsod pantallazos azules esta semana, pero ninguno desde el {0:dd/MM}" -f $evBsod[0].TimeCreated) 'Si cambiaste algo, parece que funcionó: a los 7 días del último deja de contar' }
        elseif ($bsod) { Falla ([math]::Min(30, 10 + 2 * $bsod)) "$bsod pantallazos azules en la última semana" 'Lo más importante: arriba dice qué probar (XMP de la RAM, drivers)' }

        $mods = @(Get-CimInstance Win32_PhysicalMemory); $mhz = $mods[0].ConfiguredClockSpeed; $nom = Get-RamNominal $mods[0]
        if ($nom -and $nom -gt $mhz + 50 -and -not $bsod -and -not (Test-RamAMano $mhz)) { Falla 8 "La RAM anda a $mhz MHz y es de $nom" 'Activá XMP / EXPO / DOCP en el BIOS' }

        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $pctLibre = if ($c.Size) { $c.FreeSpace * 100 / $c.Size } else { 100 }
        if ($pctLibre -lt 10) { Falla 12 ('Al disco de Windows le queda {0:N0}% libre' -f $pctLibre) 'Liberá espacio en la pestaña Espacio (arriba a la derecha)' }
        elseif ($pctLibre -lt 20) { Falla 5 ('Al disco de Windows le queda {0:N0}% libre' -f $pctLibre) 'Conviene liberar espacio: pestaña Espacio (arriba a la derecha)' }

        # salud: 0 = sano (consulta CIM directa, Get-PhysicalDisk tarda ~10 s)
        $enfermos = @(Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk | Where-Object { [int]$_.HealthStatus -ne 0 })
        if ($enfermos) { Falla 20 ("Un disco reporta problemas de salud: " + (($enfermos | ForEach-Object FriendlyName) -join ', ')) 'Hacé copia de tus archivos importantes y revisalo' }

        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' } | Select-Object -First 1
        if ($gpu.DriverDate) { $edad = [math]::Round(((Get-Date) - $gpu.DriverDate).TotalDays); if ($edad -gt 180) { Falla 5 "El driver de video es de hace $edad días" 'Actualizalo desde la página de NVIDIA o AMD' } }

        $inicio = @(Get-ProgramasInicio | Where-Object Activo).Count
        if ($inicio -gt 12) { Falla 5 "$inicio programas arrancan con Windows" 'Apagá los que no uses en la pestaña Arranque (arriba a la derecha)' }

        if ((Get-PlanActivo) -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') { Falla 4 'El plan de energía no está en Alto rendimiento' 'Se arregla solo con Todo para jugar' $true }
        if ((Get-ItemProperty $ClaveDVR).GameDVR_Enabled -ne 0 -or (Get-ItemProperty $ClaveCaptura).AppCaptureEnabled -ne 0) { Falla 4 'La Game Bar graba de fondo (cuesta FPS)' 'Se arregla solo con Todo para jugar' $true }

        # cable de red: placa Gigabit conectada a menos de 1000 Mbps (casi siempre el cable o el puerto)
        $red = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
            $_.OperationalStatus -eq 'Up' -and @($_.GetIPProperties().GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and "$($_.Address)" -ne '0.0.0.0' }).Count
        } | Select-Object -First 1
        if ($red -and "$($red.NetworkInterfaceType)" -eq 'Ethernet' -and $red.Description -match 'GbE|Gigabit|2\.5G|5G|10G' -and $red.Speed -lt 1e9) {
            Falla 8 ('El cable de red va a {0:N0} Mbps en una placa Gigabit' -f ($red.Speed / 1e6)) 'Probá otro cable (Cat5e o Cat6) u otro puerto del router'
        }

        $temp = TamMB $env:TEMP
        if ($temp -gt 1024) { Falla 3 ('Hay {0:N1} GB de archivos temporales' -f ($temp / 1024)) 'Se arregla solo con Limpieza (o Todo para jugar)' $true }

        $os = Get-CimInstance Win32_OperatingSystem
        $dias = ((Get-Date) - $os.LastBootUpTime).TotalDays
        if ($dias -gt 7) { Falla 3 ('La PC lleva {0:N0} días sin reiniciar' -f $dias) 'Reiniciala de vez en cuando: Windows termina actualizaciones y libera memoria' }
        $pctRam = 100 - $os.FreePhysicalMemory * 100 / $os.TotalVisibleMemorySize
        if ($pctRam -gt 85) { Falla 5 ('La RAM está al {0:N0}% de uso' -f $pctRam) 'Cerrá lo que no uses o tocá Modo juego' $true }

        # (en PowerShell 5 Measure-Object no acepta { $_.R }: se suman los números sueltos)
        $p = [math]::Max(0, 100 - [int](($fallas | ForEach-Object { $_.R } | Measure-Object -Sum).Sum))
        $etiqueta = if ($p -ge 90) { 'Excelente' } elseif ($p -ge 75) { 'Bien' } elseif ($p -ge 55) { 'Mejorable' } else { 'Necesita atención' }
        Out-Line ''
        Out-Line ("PUNTAJE: {0} / 100  ·  {1}" -f $p, $etiqueta) 'title'
        if ($fallas.Count) {
            Out-Line '  Qué mejorar (de lo más importante a lo menos):' 'dim'
            foreach ($f in ($fallas | Sort-Object { $_.R } -Descending)) {
                Out-Line ("  -{0,-3} {1}" -f $f.R, $f.Q) $(if ($f.R -ge 10) { 'err' } else { 'warn' })
                Out-Line ("        → {0}" -f $f.A) $(if ($f.Auto) { 'ok' } else { 'dim' })
            }
        } else { Out-Line '  Todo en orden: no hay nada importante para mejorar.' 'ok' }
        $auto = @($fallas | Where-Object { $_.Auto } | ForEach-Object { $_.Q })
        if ($sync) { $sync.Q.Enqueue(@{ Tipo = 'puntaje'; P = $p; E = $etiqueta; Auto = $auto; N = $fallas.Count }) }
        Log-Archivo "Revisión completa: $p/100 ($($fallas.Count) cosas a mejorar)"
    }

