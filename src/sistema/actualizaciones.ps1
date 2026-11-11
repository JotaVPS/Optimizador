# ================================
# ACTUALIZACIONES (desde GitHub)
# ================================
# En el repositorio hay dos archivos: Optimizador.bat y version.json
#   { "version": "3.4", "sha256": "<huella del .bat>", "notas": ["...", "..."] }
# El programa lee version.json; si hay una más nueva ofrece actualizar, baja el .bat,
# comprueba que la huella coincida (si no, lo descarta) y se reabre.

$RepoGitHub = 'JotaVPS/Optimizador'   # 'usuario/repositorio' (vacío = no busca actualizaciones)
$UrlBase = if ($RepoGitHub) { "https://raw.githubusercontent.com/$RepoGitHub/main" } else { '' }

function New-Cliente {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072   # TLS 1.2
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = "Optimizador-JVps/$Version"
    $wc.Headers['Cache-Control'] = 'no-cache'
    $wc
}

function Start-BuscarUpdate([bool]$manual) {
    $script:ProximoChequeo = (Get-Date).AddHours(20)
    if (-not $UrlBase) {
        if ($manual) { Show-Dialogo 'Actualizaciones' 'Esta copia no tiene configurado dónde buscar versiones nuevas.' 'OK' '' 'info' | Out-Null }
        return
    }
    # en segundo plano: si internet anda lento no se traba la ventana
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script:UpdBusqueda = $ps   # Handle-Update lo cierra cuando llega la respuesta
    [void]$ps.AddScript({
        param($url, $manual, $ver)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
            $wc = New-Object Net.WebClient
            $wc.Headers['User-Agent'] = "Optimizador-JVps/$ver"; $wc.Headers['Cache-Control'] = 'no-cache'
            $txt = $wc.DownloadString("$url/version.json?t=" + [DateTime]::UtcNow.Ticks)
            $sync.Q.Enqueue(@{ Tipo = 'update'; J = ($txt | ConvertFrom-Json); Manual = $manual })
        } catch { $sync.Q.Enqueue(@{ Tipo = 'update'; Error = $_.Exception.Message; Manual = $manual }) }
    }).AddArgument($UrlBase).AddArgument($manual).AddArgument($Version)
    [void]$ps.BeginInvoke()
}

function Handle-Update($m) {
    # queda abierto en la bandeja días: sin esto suma un runspace por chequeo diario
    if ($script:UpdBusqueda) { $script:UpdBusqueda.Runspace.Dispose(); $script:UpdBusqueda.Dispose(); $script:UpdBusqueda = $null }
    if ($m.Error) {
        if ($m.Manual) {
            # 404/403: hay internet, pero el lugar de las actualizaciones no responde; el resto: sin conexión
            $txt = if ($m.Error -match '\((404|403|410)\)') { "El servidor de actualizaciones no está disponible por ahora. El Optimizador sigue funcionando normal; probá más tarde." }
                   else { "No se pudo conectar para ver si hay versión nueva. Revisá que tengas internet y probá de nuevo." }
            Add-Line ("No se pudo buscar actualizaciones: " + $m.Error) 'dim'   # el detalle técnico, por si hace falta
            Show-Dialogo 'No se pudo buscar' $txt 'OK' '' 'alerta' | Out-Null
        }
        return
    }
    $j = $m.J
    if ([version]$j.version -le [version]$Version) {
        if ($m.Manual) { Show-Dialogo 'Estás al día' "Tenés la última versión (v$Version)." 'Genial' '' 'info' | Out-Null }
        return
    }
    # aviso arriba a la derecha (queda hasta que actualicen); el cartel solo salta si lo buscaron a mano
    $script:UpdPendiente = $j
    $ui.UpdPill.Content = "Actualización v$($j.version)"
    $ui.UpdPill.Visibility = 'Visible'
    $ui.BtnUpdate.Foreground = $Colores.accent
    $ui.BtnUpdate.ToolTip = "Hay una versión nueva (v$($j.version))"
    if ($m.Manual) { Ofrecer-Update }
}

function Ofrecer-Update {
    $j = $script:UpdPendiente
    if (-not $j) { return }
    $notas = if ($j.notas) { "`n`nNovedades:`n" + (($j.notas | ForEach-Object { "•  $_" }) -join "`n") } else { '' }
    $ok = Show-Dialogo "Hay una versión nueva (v$($j.version))" ("Tenés la v$Version." + $notas) 'Actualizar' 'Ahora no' 'descarga'
    if ($ok) { Install-Update $j }
}

# Actualizar se ve de punta a punta: ventana con barra (descargando %, verificando, instalando) y la app
# vieja no se cierra hasta que la nueva avisa que ya abrió (evento ..._Listo), así no queda un hueco sin nada.
$UpdMarca = Join-Path $Raiz 'actualizado.json'   # la versión nueva lo lee al abrir y muestra "¡Listo!"

function Set-UpdProgreso([int]$pct, [string]$texto) {
    $d = $script:UpdDlg
    if (-not $d) { return }
    $ancho = if ($d.Tag.Pista.ActualWidth) { $d.Tag.Pista.ActualWidth } else { 410 }   # 410 = ancho del diálogo
    $d.Tag.Barra.Width = $ancho * [math]::Min(100, [math]::Max(0, $pct)) / 100
    $d.FindName('DTexto').Text = $texto
}

function Close-UpdDialogo {
    if ($script:UpdDlg) { $script:UpdDlg.Tag.Cerrar = $true; $script:UpdDlg.Close(); $script:UpdDlg = $null }
}

function Install-Update($j) {
    if ($script:UpdEnCurso) { return }
    $script:UpdEnCurso = $j
    # el diálogo de siempre, sin botones y con una barra de progreso abajo del texto
    $d = New-Dialogo "Actualizando a v$($j.version)" 'Descargando...' '' '' 'descarga'
    $d.FindName('DSi').Visibility = 'Collapsed'; $d.FindName('DNo').Visibility = 'Collapsed'
    $pista = New-Object Windows.Controls.Border -Property @{ Height = 6; CornerRadius = 3; Margin = '0,16,0,0' }
    $pista.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Line')
    $barra = New-Object Windows.Controls.Border -Property @{ Height = 6; CornerRadius = 3; HorizontalAlignment = 'Left'; Width = 0 }
    $barra.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Grad')
    $pista.Child = $barra
    [void]$d.FindName('DTexto').Parent.Parent.Children.Insert(2, $pista)
    $d.Tag = @{ Pista = $pista; Barra = $barra; Cerrar = $false }
    # mientras actualiza no se cierra (ni con Esc): si se corta a la mitad queda en la versión vieja igual
    $d.Add_Closing({ if (-not $this.Tag.Cerrar) { $_.Cancel = $true } })
    $script:UpdDlg = $d
    $d.Show()

    # descarga en segundo plano, de a pedazos para poder mostrar el porcentaje
    $tmp = Join-Path $env:TEMP "Optimizador_v$($j.version).bat"
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script:UpdDescarga = $ps
    [void]$ps.AddScript({
        param($url, $tmp, $ver)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
            $req = [Net.HttpWebRequest]::Create($url)
            $req.UserAgent = "Optimizador-JVps/$ver"; $req.Headers['Cache-Control'] = 'no-cache'
            $resp = $req.GetResponse(); $total = $resp.ContentLength
            $in = $resp.GetResponseStream(); $out = [IO.File]::Create($tmp)
            $buf = New-Object byte[] 16384; $leido = 0; $ultimo = -1
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n); $leido += $n
                $pct = if ($total -gt 0) { [int]($leido * 100 / $total) } else { 50 }
                if ($pct -ne $ultimo) { $ultimo = $pct; $sync.Q.Enqueue(@{ Tipo = 'updprog'; P = $pct; KB = [int]($leido / 1KB); Total = [int]($total / 1KB) }) }
            }
            $out.Close(); $in.Close(); $resp.Close()
            $sync.Q.Enqueue(@{ Tipo = 'upddl'; Ruta = $tmp })
        } catch {
            if ($out) { $out.Close() }
            $sync.Q.Enqueue(@{ Tipo = 'upddl'; Error = $_.Exception.Message })
        }
    }).AddArgument("$UrlBase/Optimizador.bat?t=" + [DateTime]::UtcNow.Ticks).AddArgument($tmp).AddArgument($Version)
    [void]$ps.BeginInvoke()
}

function Handle-UpdProgreso($m) {
    $txt = if ($m.Total -gt 0) { "Descargando...  $($m.KB) KB de $($m.Total) KB" } else { "Descargando...  $($m.KB) KB" }
    Set-UpdProgreso ([int]($m.P * 0.8)) $txt   # la descarga es el 80% de la barra; el resto, verificar e instalar
}

function Finish-Update($m) {
    if ($script:UpdDescarga) { $script:UpdDescarga.Runspace.Dispose(); $script:UpdDescarga.Dispose(); $script:UpdDescarga = $null }
    $j = $script:UpdEnCurso
    $tmp = $m.Ruta
    try {
        if ($m.Error) { throw "no se pudo descargar ($($m.Error))." }
        Set-UpdProgreso 85 'Verificando que el archivo sea el original...'
        if ((Get-Hash $tmp) -ne ([string]$j.sha256).ToUpper()) { throw 'el archivo descargado no coincide con la huella publicada, así que se descartó.' }
        if ((Get-VersionArchivo $tmp) -ne [version]$j.version) { throw 'el archivo descargado no es la versión anunciada.' }
        Set-UpdProgreso 92 'Instalando...'
        $instalado = Test-Tarea
        # abierto desde la copia de Archivos de programa sin admin: no hay dónde escribir
        if ($Archivo -eq $InstBat -and -not $EsAdminAhora) { throw 'hace falta abrirlo con permisos de administrador para actualizar la instalación.' }
        # -ErrorAction Stop: con SilentlyContinue un copiado fallido pasaba como "Actualizado"
        if ($instalado -and $EsAdminAhora) { Copy-Item -LiteralPath $tmp -Destination $InstBat -Force -ErrorAction Stop }
        if ($Archivo -ne $InstBat) { Copy-Item -LiteralPath $tmp -Destination $Archivo -Force -ErrorAction Stop }
    } catch {
        Close-UpdDialogo
        $script:UpdEnCurso = $null
        Add-Line ("No se pudo actualizar: " + $_.Exception.Message) 'err'
        Show-Dialogo 'No se pudo actualizar' ("Se quedó en la v$Version.`n`n" + $_.Exception.Message) 'OK' '' 'alerta' | Out-Null
        return
    } finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Force } }

    Set-UpdProgreso 100 "Abriendo la v$($j.version)..."
    # la versión nueva lee esto para mostrar "¡Listo!" con las novedades
    if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
    @{ De = $Version; A = [string]$j.version; Notas = @($j.notas) } | ConvertTo-Json | Set-Content -LiteralPath $UpdMarca -Encoding UTF8
    # la nueva avisa por este evento cuando ya tiene la ventana abierta
    $sec = New-Object Security.AccessControl.EventWaitHandleSecurity
    $sec.AddAccessRule((New-Object Security.AccessControl.EventWaitHandleAccessRule (New-Object Security.Principal.SecurityIdentifier ([Security.Principal.WellKnownSidType]::WorldSid), $null), ([Security.AccessControl.EventWaitHandleRights]'Synchronize, Modify'), 'Allow'))
    $nuevo = $false
    $script:EvtListo = New-Object Threading.EventWaitHandle $false, ([Threading.EventResetMode]::ManualReset), 'Local\OptimizadorJvps_Listo', ([ref]$nuevo), $sec
    $script:UpdEsperaHasta = (Get-Date).AddSeconds(30)
    $script:Actualizando = $true
    # deja que la ventana nueva pase al frente (Windows no deja robar el foco si no se lo permite el que lo tiene)
    [void][JVps.Shell]::AllowSetForegroundWindow(-1)
    # reabre la versión nueva: suelta el mutex antes, si no la nueva se cree la segunda instancia
    if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose(); $script:Mutex = $null }
    # Instalado: se lanza la copia de Archivos de programa directo (hereda los permisos de admin de esta, sin aviso).
    # Por la tarea no: si esta app la abrió la tarea, sigue "en ejecución" y Windows ignora el segundo arranque
    # (MultipleInstances = IgnoreNew) aunque Start-ScheduledTask diga que anduvo.
    Start-Relanzar $instalado
    # Salir lo hace el timer cuando la nueva avisa; si a los 30 s no avisó, esta queda abierta (Update-NoAbrio)
}

function Start-Relanzar([bool]$instalado) {
    if ($instalado -and $EsAdminAhora -and (Test-Path -LiteralPath $InstExe)) { Start-Process -FilePath $InstExe -ArgumentList '--directo' }
    elseif ($instalado -and $EsAdminAhora) { Start-Oculto (Comando-Lanzar $InstBat) }
    # con el .exe se relanza él (mismos permisos que ahora, sin powershell.exe); sin él, PowerShell sin ventana
    elseif ($Exe) { Start-Process -FilePath $Exe -ArgumentList '--elevado' }
    else { Start-Oculto (Comando-Lanzar $Archivo) }
}

# reabrir el programa (para entrar o salir de Cristal: el tipo de ventana se elige al crearla).
# Mismo camino que al actualizar: la nueva avisa por el evento Listo y recién ahí se cierra esta.
function Start-Reabrir {
    Save-Cfg
    $sec = New-Object Security.AccessControl.EventWaitHandleSecurity
    $sec.AddAccessRule((New-Object Security.AccessControl.EventWaitHandleAccessRule (New-Object Security.Principal.SecurityIdentifier ([Security.Principal.WellKnownSidType]::WorldSid), $null), ([Security.AccessControl.EventWaitHandleRights]'Synchronize, Modify'), 'Allow'))
    $nuevo = $false
    $script:EvtListo = New-Object Threading.EventWaitHandle $false, ([Threading.EventResetMode]::ManualReset), 'Local\OptimizadorJvps_Listo', ([ref]$nuevo), $sec
    [void]$script:EvtListo.Reset()
    $script:UpdEsperaHasta = (Get-Date).AddSeconds(30)
    $script:Actualizando = $true; $script:Reabriendo = $true
    [void][JVps.Shell]::AllowSetForegroundWindow(-1)
    if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose(); $script:Mutex = $null }
    Start-Relanzar (Test-Tarea)
}

# la versión nueva no avisó que abrió: esta no se cierra (si no, quedaba sin ninguna abierta)
function Update-NoAbrio {
    Close-UpdDialogo
    $script:Actualizando = $false
    $script:UpdEnCurso = $null
    try { $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps') } catch { }
    $v = $script:UpdPendiente.version
    Add-Line "La v$v quedó instalada pero no se abrió sola." 'warn'
    Show-Dialogo "La v$v ya está instalada" "No se abrió sola. Cerrá esta ventana del todo (paloma de la bandeja > Salir) y abrí el Optimizador de nuevo desde el acceso directo." 'Entendido' '' 'alerta' | Out-Null
}

# la versión nueva, al abrir: avisa a la vieja que ya puede cerrarse y muestra qué cambió
function Show-Actualizado {
    try { $e = [Threading.EventWaitHandle]::OpenExisting('Local\OptimizadorJvps_Listo'); [void]$e.Set(); $e.Dispose() } catch { }
    if (-not (Test-Path -LiteralPath $UpdMarca)) { return }
    $u = Get-Content -LiteralPath $UpdMarca -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item -LiteralPath $UpdMarca -Force
    if ($u.A -ne $Version) { return }
    Show-Main
    Add-Line "Actualizado: v$($u.De) → v$Version" 'ok'
    $notas = if ($u.Notas) { "`n`nNovedades:`n" + (($u.Notas | ForEach-Object { "•  $_" }) -join "`n") } else { '' }
    Show-Dialogo "¡Listo! Ya tenés la v$Version" ("Se actualizó desde la v$($u.De)." + $notas) 'Genial' '' 'info' | Out-Null
}

