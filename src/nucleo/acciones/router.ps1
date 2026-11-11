    # ---------- REINICIAR ROUTER (Movistar Fibra) ----------
    # Entra a la página del router con la contraseña de la etiqueta (guardada cifrada para este usuario de
    # Windows en router.bin), manda la orden de reinicio y espera a que vuelvan el router e internet.
    function Hacer-ReiniciarRouter([bool]$soloProbar) {
        Out-Line $(if ($soloProbar) { 'ROUTER: PROBAR CONTRASEÑA' } else { 'REINICIAR ROUTER' }) 'title'
        $arch = Join-Path $Raiz 'router.bin'
        try {
            Add-Type -AssemblyName System.Security
            $clave = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($arch), $null, 'CurrentUser'))
        } catch { Out-Line '  No hay contraseña del router guardada: tocá Reiniciar y ponela.' 'err'; return }
        $ip = [JVps.Router]::Puerta()
        if (-not $ip) { Out-Line '  No hay conexión de red: fijate el cable o el Wi-Fi.' 'err'; return }
        $r = New-Object JVps.Router $ip
        Set-Prog 5 'Entrando al router'
        try { $falla = $r.Entrar($clave) }
        catch {
            Out-Line "  El router ($ip) no responde, ni siquiera para reiniciarlo." 'err'
            Out-Line '  Desenchufalo de la corriente 30 segundos y volvelo a enchufar.' 'dim'
            Log-Archivo 'Router: no responde para reiniciarlo'; return
        }
        if ($falla) {
            Out-Line "  $falla" 'err'
            if ($falla -like 'Contraseña*') {
                Remove-Item -LiteralPath $arch -Force -ErrorAction SilentlyContinue
                Out-Line '  Tocá Reiniciar de nuevo y poné la de la etiqueta de abajo del router ("Datos de acceso al Router").' 'dim'
            }
            Log-Archivo "Router: $falla"; return
        }
        Out-Line ("  {0,-34}{1}" -f 'Contraseña', 'correcta') 'ok'
        Set-Prog 10 'Buscando cómo reiniciarlo'
        $ruta = $r.BuscarReinicio()
        if (-not $ruta) {
            Out-Line '  Entré, pero este modelo no tiene la página de reinicio que conozco.' 'warn'
            Log-Archivo ('Router: sin página de reinicio | ' + ($r.Registro -join ' | ')); return
        }
        if ($soloProbar) { Out-Line ("  {0,-34}{1}" -f 'Reinicio', 'disponible') 'ok'; Out-Line '  Listo: cuando lo necesites, tocá Reiniciar.' 'dim'; Log-Archivo 'Router: contraseña probada'; return }

        Set-Prog 15 'Mandando la orden'
        if (-not $r.Reiniciar($ruta)) { Out-Line '  El router no aceptó la orden.' 'err'; Log-Archivo ('Router: no aceptó la orden | ' + ($r.Registro -join ' | ')); return }
        Out-Line ("  {0,-34}{1}" -f 'Orden de reinicio', 'aceptada') 'ok'
        $ping = New-Object Net.NetworkInformation.Ping
        $cron = [Diagnostics.Stopwatch]::StartNew()
        $responde = { param($h, $ms) try { $ping.Send($h, $ms).Status -eq 'Success' } catch { $false } }
        $tiempo = { '{0}:{1:00}' -f [int][math]::Floor($cron.Elapsed.TotalSeconds / 60), [int][math]::Floor($cron.Elapsed.TotalSeconds % 60) }

        Set-Prog 20 'Esperando que se apague'
        $fallos = 0
        while ($fallos -lt 3) {
            if ($cron.Elapsed.TotalSeconds -gt 60) { Out-Line '  El router no se apagó: puede que no haya tomado la orden.' 'warn'; Log-Archivo 'Router: no se apagó'; return }
            if (& $responde $ip 1000) { $fallos = 0 } else { $fallos++ }
            Start-Sleep -Milliseconds 700
        }
        Out-Line ("  {0,-34}{1}" -f 'Router', "apagado ($(& $tiempo))") 'ok'
        while (-not (& $responde $ip 1000)) {
            $s = $cron.Elapsed.TotalSeconds
            Set-Prog ([math]::Min(80, 25 + [int]($s / 140 * 55))) "Reiniciando el router... $(& $tiempo)"
            if ($s -gt 300) { Out-Line '  Tarda mucho en volver: fijate las luces. Si no vuelve, desenchufalo 30 segundos.' 'err'; Log-Archivo 'Router: no volvió en 5 min'; return }
            Start-Sleep -Seconds 1
        }
        Out-Line ("  {0,-34}{1}" -f 'Router', "prendido de nuevo ($(& $tiempo))") 'ok'
        # la fibra sincroniza después de que el router prende
        while ($true) {
            if ((& $responde '8.8.8.8' 1500) -or (& $responde '1.1.1.1' 1500)) {
                try { if ([Net.Dns]::GetHostAddresses('www.google.com').Count) { break } } catch { }
            }
            Set-Prog ([math]::Min(97, 82 + [int]($cron.Elapsed.TotalSeconds / 30))) "Esperando internet... $(& $tiempo)"
            if ($cron.Elapsed.TotalSeconds -gt 480) { Out-Line '  El router volvió pero internet no: fijate si la luz de la fibra está en rojo.' 'err'; Log-Archivo 'Router: sin internet después de reiniciar'; return }
            Start-Sleep -Milliseconds 1500
        }
        Out-Line ("  {0,-34}{1}" -f 'Internet', "de vuelta ($(& $tiempo))") 'ok'
        Out-Line ''
        Out-Line "Listo: internet volvió en $(& $tiempo)" 'title'
        Log-Archivo ('Router: reiniciado, internet volvió en {0:N0} s' -f $cron.Elapsed.TotalSeconds)
    }

