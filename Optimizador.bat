<# :
@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$Archivo='%~f0'; & ([scriptblock]::Create([IO.File]::ReadAllText($Archivo,[Text.Encoding]::UTF8))) %*"
exit /b
#>
# ================================
#  Optimizador Windows - J.vps  v3
# ================================
# Archivo único: arriba un lanzador .bat, abajo el programa en PowerShell.
# Uso: doble clic (pide permisos de administrador solo)
# Para probar sin ventana:  Optimizador.bat -Accion diagnostico | limpieza -Simular
# Para sacar una captura:   Optimizador.bat -Captura C:\ruta\captura.png
param(
    [ValidateSet('', 'limpieza', 'juego', 'todo', 'diagnostico', 'reparar', 'red', 'restaurar', 'autojuego', 'finjuego')]
    [string]$Accion = '',
    [switch]$Simular,
    [string]$Captura = '',
    [string]$Tema = '',     # solo para capturas de prueba
    [switch]$Claro,
    [string]$SinDatos = '', # solo para capturas de prueba: ej. 'ram,vram'
    [switch]$SinElevar      # lo pasa Optimizador.exe: ya pidió permisos él (con su nombre y la paloma)
)

$ErrorActionPreference = 'SilentlyContinue'
# los logs van a AppData para no ensuciar la carpeta del optimizador
$Raiz = Join-Path $env:LOCALAPPDATA 'Optimizador J.vps'
$Version = '3.13'
# el programa tal cual se abrió: si corre desde la copia instalada y la desinstalan, Instalar la reescribe desde acá
$Fuente = try { [IO.File]::ReadAllBytes($Archivo) } catch { $null }

# ================================
# UNA SOLA INSTANCIA
# ================================
# Si ya está abierto (por ejemplo en la bandeja), le avisa que se muestre y se cierra.

if (-not $Accion -and -not $Captura) {
    $creado = $false
    try { $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps', [ref]$creado) } catch { $creado = $false }
    if (-not $creado) {
        try { [void][Threading.EventWaitHandle]::OpenExisting('Local\OptimizadorJvps_Mostrar').Set() } catch { }
        exit
    }
}

# ================================
# INSTALACION (para no pedir permisos cada vez)
# ================================
# Con permiso una vez: se copia a Archivos de programa (solo admin puede modificarlo ahí) y crea una
# tarea programada "con los privilegios más altos". Después se abre lanzando esa tarea, sin aviso de permisos.
# La tarea apunta a la copia protegida, nunca a un .bat del Escritorio que cualquier programa podría cambiar.

$TareaNombre = 'Optimizador J.vps'
$InstDir = Join-Path $env:ProgramFiles 'Optimizador J.vps'
$InstBat = Join-Path $InstDir 'Optimizador.bat'

function Get-Hash($ruta) { if (Test-Path -LiteralPath $ruta) { (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash } }
function Test-Tarea { [bool](Get-ScheduledTask -TaskName $TareaNombre -ErrorAction SilentlyContinue) }
# versión escrita en un .bat del optimizador (la línea $Version = '...')
function Get-VersionArchivo($ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return [version]'0.0' }
    $m = [regex]::Match(((Get-Content -LiteralPath $ruta -TotalCount 40 -Encoding UTF8) -join "`n"), "\`$Version = '([\d.]+)'")
    if ($m.Success) { [version]$m.Groups[1].Value } else { [version]'0.0' }
}
# instalado y al día: la copia de Archivos de programa es esta versión o una más nueva
# (si abren un .bat viejo que quedó en Descargas, se abre la instalada en vez de volver para atrás)
function Test-InstaladoAlDia { (Test-Tarea) -and ((Get-VersionArchivo $InstBat) -ge [version]$Version) }

function Comando-Lanzar($ruta, $extra = '') {
    # lo que corre la tarea / el pedido de permisos: PowerShell oculto leyendo el .bat (sin pasar por cmd)
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"`$Archivo='$ruta'; & ([scriptblock]::Create([IO.File]::ReadAllText(`$Archivo,[Text.Encoding]::UTF8))) $extra`""
}

# Abierto desde Optimizador.exe: el .exe deja su ruta acá. Con él no aparece ninguna consola
# y el aviso de permisos dice "Optimizador J.vps" en vez de "Windows PowerShell".
$Exe = if ($env:OptimizadorExe -and (Test-Path -LiteralPath $env:OptimizadorExe)) { $env:OptimizadorExe } else { '' }
$InstExe = Join-Path $InstDir 'Optimizador.exe'

# PowerShell sin ventana de verdad: -WindowStyle Hidden solo la esconde después de mostrarla un instante
function Start-Oculto($argumentos) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', $argumentos
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    [void][Diagnostics.Process]::Start($psi)
}

function Install-Optimizador {
    if (-not (Test-Path $InstDir)) { New-Item -ItemType Directory -Path $InstDir | Out-Null }
    # abierto desde la copia instalada después de Desinstalar: el archivo ya no existe y no hay de dónde copiarlo
    # (antes quedaba la tarea sin programa y el acceso directo abría y cerraba)
    if ($Archivo -ne $InstBat -and (Test-Path -LiteralPath $Archivo)) { Copy-Item -LiteralPath $Archivo -Destination $InstBat -Force }
    elseif (-not (Test-Path -LiteralPath $InstBat) -and $Fuente) { [IO.File]::WriteAllBytes($InstBat, $Fuente) }
    if (-not (Test-Path -LiteralPath $InstBat)) { throw 'no se pudo copiar el programa a Archivos de programa.' }
    if ($Exe -and $Exe -ne $InstExe) { Copy-Item -LiteralPath $Exe -Destination $InstExe -Force }
    # con el .exe instalado la tarea lo usa a él: así tampoco se asoma la consola de PowerShell
    $accion = if (Test-Path -LiteralPath $InstExe) { New-ScheduledTaskAction -Execute $InstExe -Argument '--directo' }
              else { New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Comando-Lanzar $InstBat) }
    $quien = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
    # sin límite de tiempo (si no, Windows la corta a las 72 h) y prioridad normal (por defecto las tareas van más lentas)
    $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Priority 4
    Register-ScheduledTask -TaskName $TareaNombre -Action $accion -Principal $quien -Settings $ajustes -Force | Out-Null
    if ($logo) { Save-Ico $logo (Join-Path $InstDir 'paloma.ico') }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Optimizador.lnk'
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    if (Test-Path -LiteralPath $InstExe) {
        # acceso directo al .exe instalado: él lanza la tarea sin mostrar nada
        $s.TargetPath = $InstExe
        $s.Arguments = ''
        $s.WindowStyle = 1
        $s.IconLocation = "$InstExe,0"
    } else {
        # sin .exe: lanza la tarea en una ventana minimizada, así no se ve ningún cmd
        $s.TargetPath = "$env:WINDIR\System32\schtasks.exe"
        $s.Arguments = "/run /tn `"$TareaNombre`""
        $s.WindowStyle = 7
        $s.IconLocation = (Join-Path $InstDir 'paloma.ico') + ',0'
    }
    $s.Description = 'Optimizador Windows - J.vps'
    $s.Save()
}

function Uninstall-Optimizador {
    Unregister-ScheduledTask -TaskName $TareaNombre -Confirm:$false
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Optimizador.lnk'
    if (Test-Path $lnk) {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        if ($s.Arguments -match [regex]::Escape($TareaNombre) -or $s.TargetPath -eq $InstExe) { Remove-Item $lnk -Force }
    }
    # el script ya está cargado en memoria, así que se puede borrar su carpeta mientras corre
    Remove-Item -LiteralPath $InstDir -Recurse -Force
    # salvo el .exe si este programa es justo esa copia (Windows no deja borrar un .exe abierto):
    # queda anotado para que Windows lo borre al reiniciar (4 = MOVEFILE_DELAY_UNTIL_REBOOT)
    if (Test-Path -LiteralPath $InstExe) {
        [void][JVps.Shell]::MoveFileEx($InstExe, $null, 4)
        [void][JVps.Shell]::MoveFileEx($InstDir, $null, 4)
    }
}

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
        if ($m.Manual) { Show-Dialogo 'No se pudo buscar' "No se pudo consultar si hay versión nueva. ¿Hay internet?`n`n$($m.Error)" 'OK' '' 'alerta' | Out-Null }
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
    if ($instalado -and $EsAdminAhora) { Start-ScheduledTask -TaskName $TareaNombre }
    # con el .exe se relanza él (mismos permisos que ahora, sin powershell.exe); sin él, PowerShell sin ventana
    elseif ($Exe) { Start-Process -FilePath $Exe -ArgumentList '--elevado' }
    else { Start-Oculto (Comando-Lanzar $Archivo) }
    # Salir lo hace el timer cuando la nueva avisa (o a los 30 s, por si tarda)
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

# ================================
# ADMIN
# ================================

$EsAdminAhora = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# desde el .exe no se vuelve a pedir: si cancelaron su aviso, abre con las opciones de admin limitadas
if (-not $EsAdminAhora -and -not $Accion -and -not $Captura -and -not $SinElevar) {
    # Suelta el mutex antes de relanzar, si no la copia elevada se creería la segunda instancia.
    $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose()
    if (Test-InstaladoAlDia) {
        # instalado: se abre con la tarea, sin aviso de permisos
        # si Windows no deja lanzarla, sigue por el camino de pedir permisos
        try { Start-ScheduledTask -TaskName $TareaNombre -ErrorAction Stop; exit } catch { }
    }
    # no instalado (o este archivo es una versión distinta): pide permisos una vez, directo desde PowerShell oculto
    try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList (Comando-Lanzar $Archivo); exit } catch { }
    # si cancelan el aviso abre igual, con las opciones de admin limitadas
    $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps')
}

# ================================
# NUCLEO (corre en segundo plano para no congelar la ventana)
# ================================

$Core = {
    $ErrorActionPreference = 'SilentlyContinue'
    $EsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

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
        $items = if ($filtro) { Get-ChildItem -LiteralPath $ruta -Filter $filtro -Force -File } else { Get-ChildItem -LiteralPath $ruta -Recurse -Force -File }
        [math]::Round((($items | Measure-Object Length -Sum).Sum) / 1MB, 1)
    }

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
                # lo que está en uso no se puede borrar: se saltea sin error
                if ($l.Filtro) { Get-ChildItem -LiteralPath $l.Ruta -Filter $l.Filtro -Force -File | Remove-Item -Force }
                else { Get-ChildItem -LiteralPath $l.Ruta -Force | Remove-Item -Recurse -Force }
            }
            $despues = if ($Simular) { 0 } else { TamMB $l.Ruta $l.Filtro }
            $mb = [math]::Max(0, [math]::Round($antes - $despues, 1))
            $total += $mb
            Out-Line ("  {0,-30}{1,11:N1} MB" -f $l.Nombre, $mb) 'ok'
        }
        if (-not $Simular) { ipconfig /flushdns | Out-Null; Out-Line ("  {0,-30}{1,14}" -f 'Caché de DNS', 'vaciada') 'ok' }
        $verbo = if ($Simular) { 'Se liberarían' } else { 'Liberado' }
        Out-Line ''
        Out-Line ("{0}: {1:N0} MB" -f $verbo, $total) 'title'
        Log-Archivo ("Limpieza{0}: {1:N0} MB" -f $(if ($Simular) { ' (simulada)' } else { '' }), $total)
    }

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
    function Get-PlanActivo { if ((powercfg /getactivescheme) -join ' ' -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})') { $Matches[1].ToLower() } }

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
            powercfg /setactive SCHEME_MIN | Out-Null
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
        if ($r.Plan) { powercfg /setactive $r.Plan | Out-Null }
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

    # ---------- PUNTO DE RESTAURACIÓN (antes de Red y Reparar) ----------
    function Crear-PuntoRestauracion($motivo, [int]$pct = 2) {
        Set-Prog $pct 'Creando punto de restauración'
        Out-Line '  Creando punto de restauración de Windows (puede tardar un minuto)...' 'dim'
        $antes = @(Get-ComputerRestorePoint).Count
        $error_ = $null
        try { Checkpoint-Computer -Description "Optimizador J.vps: antes de $motivo" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue }
        catch { $error_ = $_.Exception.Message }
        if (@(Get-ComputerRestorePoint).Count -gt $antes) {
            Out-Line '  Punto de restauración creado: si algo sale mal, Inicio > "Recuperación" > Abrir Restaurar sistema.' 'ok'
        } elseif ($error_) {
            # casi siempre: la Protección del sistema está apagada en C:
            Out-Line '  No se pudo crear el punto de restauración (¿Protección del sistema apagada en C:?). Se sigue igual.' 'warn'
        } else {
            # Windows hace como mucho uno por día: si ya hubo uno, usa ese
            Out-Line '  Windows ya tiene un punto de restauración de hoy: se usa ese.' 'dim'
        }
    }

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

    function Hacer-Diagnostico {
        Out-Line 'DIAGNÓSTICO' 'title'
        Set-Prog 15 'Memoria RAM'
        $mods = @(Get-CimInstance Win32_PhysicalMemory)
        $totalGB = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
        $mhz = $mods[0].ConfiguredClockSpeed
        Out-Line ("  RAM: {0} GB en {1} módulos a {2} MHz" -f $totalGB, $mods.Count, $mhz) 'ok'
        $nominal = Get-RamNominal $mods[0]
        $hayBsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-7) }).Count
        if ($nominal -and $nominal -gt $mhz + 50) {
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
        Get-Volume | Where-Object DriveLetter | Sort-Object DriveLetter | ForEach-Object {
            $libre = [math]::Round($_.SizeRemaining / 1GB); $tot = [math]::Round($_.Size / 1GB)
            $pct = if ($tot) { [math]::Round($libre * 100 / $tot) } else { 0 }
            $k = if ($pct -lt 10) { 'err' } elseif ($pct -lt 20) { 'warn' } else { 'ok' }
            Out-Line ("  Disco {0}:  {1} GB libres de {2} GB ({3}%)" -f $_.DriveLetter, $libre, $tot, $pct) $k
        }
        Get-PhysicalDisk | ForEach-Object {
            $sano = $_.HealthStatus -eq 'Healthy'
            Out-Line ("    {0}: {1}" -f $_.FriendlyName.Trim(), $(if ($sano) { 'sano' } else { $_.HealthStatus })) $(if ($sano) { 'dim' } else { 'err' })
        }

        Set-Prog 75 'Arranque y energía'
        $inicio = @(Get-CimInstance Win32_StartupCommand)
        if ($inicio.Count -gt 15) {
            Out-Line ("  Programas que arrancan con Windows: {0}" -f $inicio.Count) 'warn'
            Out-Line '    Desactivá los que no uses en Ctrl+Shift+Esc > Aplicaciones de arranque' 'dim'
        } else { Out-Line ("  Programas que arrancan con Windows: {0}" -f $inicio.Count) 'ok' }
        $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled
        if ($hb -eq 1) { Out-Line '  Inicio rápido: activado (si se cuelga al apagar, desactivalo)' 'warn' }
        else { Out-Line '  Inicio rápido: desactivado' 'ok' }

        Set-Prog 90 'Placa de video'
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' } | Select-Object -First 1
        if ($gpu) {
            $edad = [math]::Round(((Get-Date) - $gpu.DriverDate).TotalDays)
            Out-Line ("  {0}: driver de hace {1} días" -f $gpu.Name, $edad) $(if ($edad -gt 180) { 'warn' } else { 'ok' })
        }
        Log-Archivo "Diagnóstico: RAM $mhz MHz, $($bsod.Count) BSOD / $($apagon.Count) apagones en 7 días"
    }

    # ---------- REPARAR ----------
    function Hacer-Reparar {
        Out-Line 'REPARAR WINDOWS' 'title'
        if (-not $EsAdmin) { Out-Line '  Necesita permisos de administrador. Abrilo desde Optimizador.bat y aceptá el aviso.' 'err'; return }
        Out-Line '  Tarda entre 10 y 30 minutos. No apagues la PC.' 'warn'
        Crear-PuntoRestauracion 'Reparar Windows'
        Set-Prog 5 'DISM: reparando la imagen de Windows'
        & DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object {
            $t = ("$_" -replace "`0", '').Trim()
            if ($t -match '(\d+)[\.,]\d+%') { Set-Prog (5 + [int]$Matches[1] / 2) 'DISM: reparando la imagen de Windows' }
            elseif ($t -and $t -notmatch '^\[') { Out-Line "  $t" 'dim' }
        }
        Set-Prog 55 'SFC: revisando archivos del sistema'
        & sfc /scannow 2>&1 | ForEach-Object {
            $t = ("$_" -replace "`0", '').Trim()
            if ($t -match '(\d+)\s*%') { Set-Prog (55 + [int]$Matches[1] * 45 / 100) 'SFC: revisando archivos del sistema' }
            elseif ($t) { Out-Line "  $t" 'dim' }
        }
        Out-Line ''
        Out-Line 'Reparación terminada.' 'title'
        Log-Archivo 'Reparar: DISM + SFC'
    }

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
        $q = (powercfg /q SCHEME_CURRENT $SubWifi $SetWifi) -join "`n"
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
            $w = (netsh wlan show interfaces) -join "`n"
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
            netsh int tcp set global autotuninglevel=normal | Out-Null
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
            powercfg /setacvalueindex SCHEME_CURRENT $SubWifi $SetWifi 0 | Out-Null
            powercfg /setactive SCHEME_CURRENT | Out-Null
            Out-Line ("  {0,-44}{1}" -f 'Wi-Fi enchufado', 'rendimiento máximo') 'ok'
        }
        ipconfig /flushdns | Out-Null
        netsh interface ip delete arpcache | Out-Null
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
        if ($nivel) { netsh int tcp set global autotuninglevel=$nivel | Out-Null }
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
            powercfg /setacvalueindex SCHEME_CURRENT $SubWifi $SetWifi $r.Wifi.AC | Out-Null
            powercfg /setactive SCHEME_CURRENT | Out-Null
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

    function Invoke-Accion($a) {
        switch ($a) {
            'limpieza'    { Hacer-Limpieza }
            'juego'       { Hacer-ModoJuego }
            'todo'        {
                Hacer-Limpieza; Out-Line ''; Hacer-ModoJuego; Out-Line ''
                if ($EsAdmin) { Hacer-AjustesJuego; Out-Line '' } else { Out-Line '  Plan de energía y Game Bar: necesitan permisos de administrador.' 'warn'; Out-Line '' }
                Out-Line 'Sistema listo para jugar' 'title'
            }
            'diagnostico' { Hacer-Diagnostico }
            'reparar'     { Hacer-Reparar }
            'red'         { Hacer-Red }
            'restaurar'   { Hacer-Restaurar }
            # modo juego automático: al abrir un juego de la lista / al cerrarlo
            'autojuego'   { Hacer-ModoJuego; if ($EsAdmin) { Out-Line ''; Hacer-AjustesJuego } }
            'finjuego'    {
                Out-Line 'FIN DEL MODO JUEGO' 'title'
                if (Restaurar-Juego) { Out-Line '  Plan de energía y Game Bar: como estaban antes del juego.' 'ok' }
                else { Out-Line '  No había nada para volver atrás.' 'dim' }
            }
        }
        Set-Prog 100 'Listo'
    }
}

# ================================
# MODO CONSOLA (pruebas)
# ================================

if ($Accion) {
    $sync = $null
    . ([scriptblock]::Create($Core.ToString()))
    Invoke-Accion $Accion
    return
}

# ================================
# VENTANA
# ================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Funciones de Windows que WPF no trae
Add-Type -Namespace JVps -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string origen, string destino, int flags);
[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int procesoId);
'@
# Identidad propia: sin esto la barra de tareas agrupa con PowerShell y muestra su ícono en vez de la paloma
[void][JVps.Shell]::SetCurrentProcessExplicitAppUserModelID('JVps.Optimizador')

# La app se crea antes que las ventanas: los colores del tema viven en sus recursos y todas las ventanas los leen
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'

# ---------- carteles propios (reemplazan los MessageBox grises de Windows) ----------
[xml]$dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize" Topmost="True" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Pri" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryFg}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="{DynamicResource Grad}" Padding="20,9">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Sec" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="Transparent" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="18,8">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="DBox" Margin="18" CornerRadius="16" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="24,22">
    <Border.Effect><DropShadowEffect BlurRadius="26" ShadowDepth="5" Opacity="0.5" Color="Black"/></Border.Effect>
    <StackPanel Width="410">
      <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
        <Grid Width="42" Height="42" Margin="0,0,14,0">
          <Ellipse Fill="{DynamicResource AccentSoft}"/>
          <TextBlock x:Name="DIcon" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock x:Name="DTitulo" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource Text}" VerticalAlignment="Center" TextWrapping="Wrap" Width="350"/>
      </StackPanel>
      <ScrollViewer MaxHeight="400" VerticalScrollBarVisibility="Auto">
        <TextBlock x:Name="DTexto" FontSize="13" Foreground="{DynamicResource Muted}" TextWrapping="Wrap" LineHeight="20"/>
      </ScrollViewer>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
        <Button x:Name="DNo" Style="{StaticResource Sec}" Margin="0,0,10,0"/>
        <Button x:Name="DSi" Style="{StaticResource Pri}"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

function New-Dialogo([string]$Titulo, [string]$Texto, [string]$Si = 'Aceptar', [string]$No = '', [string]$Icono = 'info') {
    $iconos = @{ info = 0xE946; pregunta = 0xE897; alerta = 0xE7BA; descarga = 0xE896; escudo = 0xEA18 }
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dlgXaml))
    $d.FindName('DIcon').Text = [char]$iconos[$Icono]
    $d.FindName('DTitulo').Text = $Titulo
    $d.FindName('DTexto').Text = $Texto
    $bSi = $d.FindName('DSi'); $bSi.Content = $Si
    $bNo = $d.FindName('DNo'); $bNo.Content = $No
    if (-not $No) { $bNo.Visibility = 'Collapsed' }
    $bSi.Add_Click({ [Windows.Window]::GetWindow($this).DialogResult = $true })
    $bNo.Add_Click({ [Windows.Window]::GetWindow($this).DialogResult = $false })
    $d.FindName('DBox').Add_MouseLeftButtonDown({ [Windows.Window]::GetWindow($this).DragMove() })
    $d.Add_KeyDown({
        if ($_.Key -eq 'Escape') { $this.DialogResult = $false }
        elseif ($_.Key -eq 'Enter') { $this.DialogResult = $true }
    })
    if ($win -and $win.IsVisible) { $d.Owner = $win; $d.WindowStartupLocation = 'CenterOwner' }
    else { $d.WindowStartupLocation = 'CenterScreen' }
    $d
}
# devuelve $true si eligió el botón principal
function Show-Dialogo([string]$Titulo, [string]$Texto, [string]$Si = 'Aceptar', [string]$No = '', [string]$Icono = 'info') {
    [bool](New-Dialogo $Titulo $Texto $Si $No $Icono).ShowDialog()
}

function Set-VentanaHerramienta($ventana, [bool]$sinFoco) {
    # WS_EX_TOOLWINDOW: no aparece en Alt+Tab ni en la barra de tareas
    # WS_EX_NOACTIVATE: al hacerle click no le saca el foco al juego
    $h = (New-Object Windows.Interop.WindowInteropHelper $ventana).EnsureHandle()
    $ex = [JVps.Shell]::GetWindowLong($h, -20)
    $ex = ($ex -bor 0x80) -band (-bnot 0x40000)
    if ($sinFoco) { $ex = $ex -bor 0x08000000 }
    [void][JVps.Shell]::SetWindowLong($h, -20, $ex)
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimizador" Width="1000" Height="640" MinWidth="860" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI">
  <Window.Resources>
    <!-- los colores vienen del tema activo (Set-Tema), por eso todo usa DynamicResource -->

    <Style x:Key="Card" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="14" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="18,16">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Hover}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Pressed}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryFg}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="14" Background="{DynamicResource Grad}" Padding="22,18">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.9"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Line}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" CornerRadius="3" Background="{DynamicResource Line}"/>
              <Border x:Name="PART_Indicator" CornerRadius="3" Background="{DynamicResource Grad}" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Stat" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Panel}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="14,12"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
    </Style>
    <Style x:Key="StatLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style x:Key="StatValue" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="19"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="22"/>
      <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="CardSub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="Margin" Value="0,3,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="18" Background="{DynamicResource Bg}" BorderBrush="{DynamicResource Line}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="48"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="34"/>
      </Grid.RowDefinitions>

      <!-- barra de titulo -->
      <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0,0,0">
          <Ellipse x:Name="LogoSmall" Width="18" Height="18" Fill="{DynamicResource Grad}"/>
          <TextBlock Text="Optimizador Windows" Foreground="{DynamicResource Muted}" FontSize="12" Margin="10,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,4,8,0">
          <!-- aparece solo cuando hay versión nueva; el botón de al lado busca a mano -->
          <Button x:Name="UpdPill" Content="Actualización disponible" Cursor="Hand" Margin="0,0,6,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Ver novedades y actualizar">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="b" CornerRadius="11" Background="{DynamicResource Grad}" Padding="11,4">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource PrimaryFg}" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ContentPresenter VerticalAlignment="Center" TextElement.FontSize="11.5" TextElement.FontWeight="SemiBold" TextElement.Foreground="{DynamicResource PrimaryFg}"/>
                  </StackPanel>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
          <Button x:Name="BtnUpdate" Style="{StaticResource WinBtn}" Content="&#xE895;" FontSize="14" ToolTip="Buscar actualizaciones"/>
          <Button x:Name="BtnTema" Style="{StaticResource WinBtn}" Content="&#xE790;" FontSize="14" ToolTip="Tema"/>
          <Button x:Name="BtnOverlay" Style="{StaticResource WinBtn}" Content="&#xE7F4;" FontSize="14" ToolTip="Datos en pantalla (Ctrl+Shift+O)"/>
          <Button x:Name="BtnMin" Style="{StaticResource WinBtn}" Content="&#xE921;"/>
          <Button x:Name="BtnClose" Style="{StaticResource WinBtn}" Content="&#xE8BB;"/>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1" Margin="26,4,26,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="1.25*"/>
          <ColumnDefinition Width="22"/>
          <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- izquierda -->
        <DockPanel Grid.Column="0" LastChildFill="True">
          <StackPanel DockPanel.Dock="Top">
            <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
              <!-- logo: la paloma en un círculo con aro degradé -->
              <Grid Width="64" Height="64" Margin="0,0,16,0" VerticalAlignment="Center">
                <Ellipse Fill="{DynamicResource Grad}"/>
                <Ellipse x:Name="LogoBig" Width="58" Height="58" Fill="{DynamicResource Panel}"/>
              </Grid>
              <StackPanel VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="Optimizador" FontSize="32" FontWeight="Bold" Foreground="{DynamicResource Grad}"/>
                  <Border x:Name="AdminBadge" CornerRadius="8" Padding="8,3" Margin="12,6,0,0" VerticalAlignment="Center" Background="{DynamicResource AccentSoft}">
                    <TextBlock x:Name="AdminText" Text="ADMIN" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
                  </Border>
                </StackPanel>
                <TextBlock x:Name="SubTitle" Text="by J.vps" Foreground="{DynamicResource Muted}" FontSize="12.5" Margin="2,0,0,0"/>
              </StackPanel>
            </StackPanel>

            <UniformGrid Columns="4" Margin="0,0,-10,18">
              <Border Style="{StaticResource Stat}">
                <StackPanel><TextBlock Text="MEMORIA" Style="{StaticResource StatLabel}"/><TextBlock x:Name="StatRam" Text="-" Style="{StaticResource StatValue}"/><TextBlock x:Name="StatRamSub" Text="" Style="{StaticResource StatLabel}"/></StackPanel>
              </Border>
              <!-- con varios discos: clic en la tarjeta abre el menú para elegir cuál ver -->
              <Border x:Name="DiskCard" Style="{StaticResource Stat}">
                <StackPanel>
                  <DockPanel>
                    <TextBlock x:Name="StatDiskNav" DockPanel.Dock="Right" Text="" FontFamily="Segoe MDL2 Assets" FontSize="10" VerticalAlignment="Center" Foreground="{DynamicResource Accent}"/>
                    <TextBlock x:Name="StatDiskLabel" Text="DISCO C:" Style="{StaticResource StatLabel}"/>
                  </DockPanel>
                  <TextBlock x:Name="StatDisk" Text="-" Style="{StaticResource StatValue}"/><TextBlock x:Name="StatDiskSub" Text="" Style="{StaticResource StatLabel}"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Stat}">
                <StackPanel><TextBlock Text="ESTABILIDAD" Style="{StaticResource StatLabel}"/><TextBlock x:Name="StatBsod" Text="-" Style="{StaticResource StatValue}"/><TextBlock x:Name="StatBsodSub" Text="" Style="{StaticResource StatLabel}"/></StackPanel>
              </Border>
              <Border Style="{StaticResource Stat}">
                <StackPanel><TextBlock Text="ENCENDIDA" Style="{StaticResource StatLabel}"/><TextBlock x:Name="StatUp" Text="-" Style="{StaticResource StatValue}"/><TextBlock x:Name="StatUpSub" Text="" Style="{StaticResource StatLabel}"/></StackPanel>
              </Border>
            </UniformGrid>

            <Button x:Name="BtnTodo" Style="{StaticResource Primary}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="26" VerticalAlignment="Center" Margin="0,0,16,0"/>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Todo para jugar" FontSize="18" FontWeight="Bold"/>
                  <TextBlock Text="Limpieza, apps de fondo, energía al máximo y Game Bar sin grabar" FontSize="12" Opacity="0.8"/>
                </StackPanel>
                <TextBlock Grid.Column="2" Text="&#xE72A;" FontFamily="Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center"/>
              </Grid>
            </Button>
            <!-- modo juego automático: se activa solo al abrir un juego de la lista y se deshace al cerrarlo -->
            <Border Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="12" Padding="16,10" Margin="0,0,0,12">
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock x:Name="AutoJuegosLink" Text="Elegir juegos" Foreground="{DynamicResource Accent}" FontSize="12" Cursor="Hand" VerticalAlignment="Center" Margin="0,0,16,0"/>
                  <Border x:Name="AutoToggle" Width="34" Height="18" CornerRadius="9" Cursor="Hand" Background="{DynamicResource Line}" ToolTip="Prender o apagar">
                    <Ellipse x:Name="AutoDot" Width="12" Height="12" Fill="White" HorizontalAlignment="Left" Margin="3,0"/>
                  </Border>
                </StackPanel>
                <TextBlock Text="&#xE7FC;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource Accent}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Modo juego automático" Foreground="{DynamicResource Text}" FontSize="13" FontWeight="SemiBold"/>
                  <TextBlock x:Name="AutoSub" Text="" Foreground="{DynamicResource Muted}" FontSize="11.5" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
              </DockPanel>
            </Border>
          </StackPanel>

          <UniformGrid Columns="3" Rows="2" Margin="-6,-6,-6,14">
            <Button x:Name="BtnLimpieza" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE74D;" Style="{StaticResource Icon}"/><TextBlock Text="Limpieza" Style="{StaticResource CardTitle}"/><TextBlock Text="Temporales y cachés" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
            <Button x:Name="BtnJuego" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE7FC;" Style="{StaticResource Icon}"/><TextBlock Text="Modo juego" Style="{StaticResource CardTitle}"/><TextBlock Text="Cierra apps de fondo" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
            <Button x:Name="BtnRed" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE701;" Style="{StaticResource Icon}"/><TextBlock Text="Red" Style="{StaticResource CardTitle}"/><TextBlock Text="Menos picos y cortes" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
            <Button x:Name="BtnDiag" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE9D9;" Style="{StaticResource Icon}"/><TextBlock Text="Diagnóstico" Style="{StaticResource CardTitle}"/><TextBlock Text="RAM, pantallazos y discos" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
            <Button x:Name="BtnReparar" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE90F;" Style="{StaticResource Icon}"/><TextBlock Text="Reparar Windows" Style="{StaticResource CardTitle}"/><TextBlock Text="DISM + SFC (10-30 min)" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
            <Button x:Name="BtnRestaurar" Style="{StaticResource Card}" Margin="6">
              <StackPanel><TextBlock Text="&#xE777;" Style="{StaticResource Icon}"/><TextBlock Text="Restaurar ajustes" Style="{StaticResource CardTitle}"/><TextBlock Text="Red y Todo para jugar" Style="{StaticResource CardSub}"/></StackPanel>
            </Button>
          </UniformGrid>
        </DockPanel>

        <!-- derecha: actividad -->
        <Border Grid.Column="2" CornerRadius="14" Background="{DynamicResource LogBg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="18,16" Margin="0,0,0,14">
          <DockPanel>
            <StackPanel DockPanel.Dock="Top">
              <DockPanel>
                <TextBlock Text="Actividad" Foreground="{DynamicResource Text}" FontSize="14" FontWeight="SemiBold"/>
                <TextBlock x:Name="Pct" Text="" Foreground="{DynamicResource Muted}" FontSize="12" HorizontalAlignment="Right"/>
              </DockPanel>
              <TextBlock x:Name="Status" Text="Elegí una opción para empezar" Foreground="{DynamicResource Muted}" FontSize="12" Margin="0,6,0,8" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="Prog" Minimum="0" Maximum="100" Value="0" Margin="0,0,0,14"/>
            </StackPanel>
            <RichTextBox x:Name="Log" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Text}"
                         FontFamily="Cascadia Mono, Consolas" FontSize="11.5" VerticalScrollBarVisibility="Auto" IsDocumentEnabled="False">
              <FlowDocument PagePadding="0"/>
            </RichTextBox>
          </DockPanel>
        </Border>
      </Grid>

      <!-- pie -->
      <DockPanel Grid.Row="2" Margin="26,0,26,10">
        <TextBlock x:Name="Footer" Text="Hecho por J.vps · no borra archivos personales" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="InstLink" Text="Instalar (abrir sin permisos)" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center" Cursor="Hand" Margin="0,0,18,0" Visibility="Collapsed"/>
          <TextBlock x:Name="UninstLink" Text="Desinstalar" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center" Cursor="Hand" Margin="0,0,18,0" Visibility="Collapsed"/>
          <TextBlock x:Name="InfoLink" Text="¿Qué hace cada botón?" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center" Cursor="Hand" Margin="0,0,18,0"/>
          <TextBlock x:Name="LogLink" Text="Abrir registro" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center" Cursor="Hand"/>
        </StackPanel>
      </DockPanel>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    if ($n) { $ui[$n] = $win.FindName($n) }
}

$bc = New-Object Windows.Media.BrushConverter
# Colores que pinta el código (log, alertas, menú). Set-Tema los rellena; se modifica la tabla, no se reemplaza,
# porque los eventos de la ventana la leen por referencia.
$Colores = @{}

# ================================
# TEMAS
# ================================

# acento: [color principal, segundo color del degradé, texto sobre el botón grande]
$Temas = [ordered]@{
    Esmeralda = @{ Nombre = 'Esmeralda';  A = '#22C55E'; B = '#06B6D4'; Fg = '#06130B' }
    Violeta   = @{ Nombre = 'Violeta';    A = '#A855F7'; B = '#6366F1'; Fg = '#FFFFFF' }
    Rojo      = @{ Nombre = 'Rojo gamer'; A = '#FF1E3C'; B = '#B0001E'; Fg = '#FFFFFF' }
    Oceano    = @{ Nombre = 'Océano';     A = '#0EA5E9'; B = '#22D3EE'; Fg = '#04131C' }
    Atardecer = @{ Nombre = 'Atardecer';  A = '#F59E0B'; B = '#EC4899'; Fg = '#1A0F02' }
    Rosa      = @{ Nombre = 'Rosa';       A = '#EC4899'; B = '#A855F7'; Fg = '#FFFFFF' }
}
$Bases = @{
    Oscuro = @{
        Bg = '#0D1117'; Panel = '#151B23'; Line = '#242C38'; Text = '#E6EDF3'; Muted = '#8B95A3'; Faint = '#5B6573'
        Hover = '#18212B'; Pressed = '#1C2833'; LogBg = '#0A0E13'; OvBg = '#E00D1117'
        MenuBg = '#1C2128'; MenuLine = '#30363D'; MenuHover = '#2A313C'; ToggleOff = '#3A4350'; WarnSoft = '#3A2A0A'
        info = '#C9D1D9'; ok = '#4ADE80'; warn = '#FBBF24'; err = '#F87171'; dim = '#6B7684'
    }
    Claro = @{
        Bg = '#F4F6F9'; Panel = '#FFFFFF'; Line = '#E3E8EF'; Text = '#0F172A'; Muted = '#64748B'; Faint = '#94A3B8'
        Hover = '#F1F5F9'; Pressed = '#E2E8F0'; LogBg = '#F8FAFC'; OvBg = '#EBFFFFFF'
        MenuBg = '#FFFFFF'; MenuLine = '#E3E8EF'; MenuHover = '#F1F5F9'; ToggleOff = '#CBD5E1'; WarnSoft = '#FEF3C7'
        info = '#334155'; ok = '#15803D'; warn = '#B45309'; err = '#DC2626'; dim = '#94A3B8'
    }
}

function Set-Tema([string]$nombre, [bool]$claro, [bool]$inicial = $false) {
    if (-not $Temas.Contains($nombre)) { $nombre = 'Esmeralda' }
    $t = $Temas[$nombre]
    $base = if ($claro) { $Bases.Claro } else { $Bases.Oscuro }
    $R = $app.Resources
    foreach ($k in 'Bg', 'Panel', 'Line', 'Text', 'Muted', 'Faint', 'Hover', 'Pressed', 'LogBg', 'OvBg', 'MenuBg', 'MenuLine') {
        $R[$k] = $bc.ConvertFromString($base[$k])
    }
    $R['Accent'] = $bc.ConvertFromString($t.A)
    $R['Accent2'] = $bc.ConvertFromString($t.B)
    $R['PrimaryFg'] = $bc.ConvertFromString($t.Fg)
    $R['AccentSoft'] = $bc.ConvertFromString(('#26' + $t.A.Substring(1)))
    $R['AccentLine'] = $bc.ConvertFromString(('#44' + $t.A.Substring(1)))
    $grad = New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($t.A)), ([Windows.Media.ColorConverter]::ConvertFromString($t.B)), (New-Object Windows.Point 0, 0), (New-Object Windows.Point 1, 1)
    # .BaseObject: New-Object lo envuelve en un PSObject y WPF no lo reconoce como pincel
    $R['Grad'] = $grad.psobject.BaseObject

    foreach ($k in 'info', 'ok', 'warn', 'err', 'dim') { $Colores[$k] = $bc.ConvertFromString($base[$k]) }
    $Colores.title = if ($claro) { $R['Accent'] } else { $R['Accent2'] }
    $Colores.accent = $R['Accent']
    $Colores.text = $R['Text']; $Colores.muted = $R['Muted']
    $Colores.hover = $bc.ConvertFromString($base.MenuHover); $Colores.menuLine = $R['MenuLine']
    $Colores.toggleOff = $bc.ConvertFromString($base.ToggleOff); $Colores.warnSoft = $bc.ConvertFromString($base.WarnSoft)

    $cfg.Tema = $nombre; $cfg.Claro = $claro
    if ($inicial) { return }
    # repinta lo que el código ya había coloreado
    foreach ($p in $ui.Log.Document.Blocks) { foreach ($r in $p.Inlines) { if ($r.Tag) { $r.Foreground = $Colores[$r.Tag] } } }
    Apply-Admin
    Update-Stats
    $ui.BtnOverlay.Foreground = if ($ov.IsVisible) { $Colores.accent } else { $Colores.muted }
    $ui.BtnUpdate.Foreground = if ($script:UpdPendiente) { $Colores.accent } else { $Colores.muted }
    if (Get-Command Set-AutoUI -ErrorAction SilentlyContinue) { Set-AutoUI }   # el interruptor toma el color del tema
    if ($ov.IsVisible) { Update-Overlay }
    Save-Cfg
}

function Show-MenuTemas {
    $e = @(@{ T = 'head'; Texto = 'COLOR' })
    foreach ($k in $Temas.Keys) {
        $t = $Temas[$k]
        # muestra: circulito con el degradé del tema, y un tilde si es el actual
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        if ($k -eq $cfg.Tema) {
            $ok = New-Object Windows.Controls.TextBlock
            $ok.Text = [char]0xE73E; $ok.FontFamily = 'Segoe MDL2 Assets'; $ok.FontSize = 12; $ok.Foreground = $Colores.accent
            $ok.VerticalAlignment = 'Center'; $ok.Margin = New-Object Windows.Thickness 0, 0, 10, 0
            [void]$sp.Children.Add($ok)
        }
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 16; $dot.Height = 16
        $dot.Fill = (New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($t.A)), ([Windows.Media.ColorConverter]::ConvertFromString($t.B)), 45).psobject.BaseObject
        [void]$sp.Children.Add($dot)
        $e += @{ T = 'item'; Texto = $t.Nombre; Der = $sp; A = [scriptblock]::Create("Set-Tema '$k' `$cfg.Claro") }
    }
    $e += @{ T = 'sep' }
    $e += @{ T = 'toggle'; Texto = 'Modo claro'; On = [bool]$cfg.Claro; A = { Set-Tema $cfg.Tema (-not $cfg.Claro) } }
    Show-Menu $e
}

$ui.SubTitle.Text = "by J.vps  ·  v$Version"

# ---------- logo (la paloma va embebida en base64 al final del archivo) ----------
function New-Logo {
    $ms = New-Object IO.MemoryStream (, [Convert]::FromBase64String($LogoB64))
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.StreamSource = $ms; $bi.EndInit(); $bi.Freeze()
    $bi
}
function Save-Ico($bitmap, $ruta) {
    # .ico con un PNG adentro, para que un acceso directo pueda usar la paloma de ícono
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $png = New-Object IO.MemoryStream; $enc.Save($png); $bytes = $png.ToArray()
    $fs = [IO.File]::Create($ruta); $w = New-Object IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$bytes.Length); $w.Write([uint32]22)
    $w.Write($bytes); $w.Close()
}
$lineaLogo = [IO.File]::ReadAllLines($Archivo) | Where-Object { $_.StartsWith('#LOGO:') } | Select-Object -First 1
$LogoB64 = if ($lineaLogo) { $lineaLogo.Substring(6).Trim() } else { '' }
if ($LogoB64) {
    $logo = New-Logo
    foreach ($el in $ui.LogoBig, $ui.LogoSmall) {
        $brush = New-Object Windows.Media.ImageBrush $logo
        $brush.Stretch = 'UniformToFill'
        $el.Fill = $brush
    }
    $win.Icon = $logo
    $ico = Join-Path $Raiz 'paloma.ico'
    if (-not (Test-Path $ico)) {
        if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
        Save-Ico $logo $ico
    }
}
function Apply-Admin {
    if (-not $EsAdminAhora) {
        $ui.AdminBadge.Background = $Colores.warnSoft
        $ui.AdminText.Text = 'SIN ADMIN'
        $ui.AdminText.Foreground = $Colores.warn
    }
}

function Add-Line([string]$texto, [string]$tipo = 'info') {
    $p = New-Object Windows.Documents.Paragraph
    $p.Margin = New-Object Windows.Thickness 0, 0, 0, 2
    $r = New-Object Windows.Documents.Run $texto
    $r.Foreground = $Colores[$tipo]
    $r.Tag = $tipo   # para repintarlo si cambian el tema
    if ($tipo -eq 'title') { $r.FontWeight = 'Bold' }
    $p.Inlines.Add($r)
    $ui.Log.Document.Blocks.Add($p)
    $ui.Log.ScrollToEnd()
}

function Update-Stats {
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $os = Get-CimInstance Win32_OperatingSystem
    $ui.StatRam.Text = '{0} GB' -f (($mods | Measure-Object Capacity -Sum).Sum / 1GB)
    $ui.StatRamSub.Text = '{0} MHz' -f $mods[0].ConfiguredClockSpeed
    Show-Disco
    $n = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-7) }).Count
    if ($n -eq 0) { $ui.StatBsod.Text = 'Estable'; $ui.StatBsod.Foreground = $Colores.ok }
    else { $ui.StatBsod.Text = "$n BSOD"; $ui.StatBsod.Foreground = $Colores.err }
    $ui.StatBsodSub.Text = 'Últimos 7 días'
    $up = (Get-Date) - $os.LastBootUpTime
    $ui.StatUp.Text = if ($up.TotalDays -ge 1) { '{0:N0} d' -f [math]::Floor($up.TotalDays) }
                      elseif ($up.TotalHours -ge 1) { '{0:N0} h' -f [math]::Floor($up.TotalHours) }
                      else { '{0:N0} min' -f [math]::Floor($up.TotalMinutes) }
    $ui.StatUpSub.Text = 'Sin reiniciar'
    $ui.StatUp.Foreground = if ($up.TotalDays -gt 7) { $Colores.warn } else { $Colores.text }
}

# ---------- tarjeta de disco: con varios discos, clic pasa al siguiente ----------
# solo discos fijos (sin pendrives ni lectoras); el elegido queda guardado en la config
function Get-Discos { @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size } | Sort-Object DriveLetter) }
function Get-IndiceDisco($discos) {
    $letras = @($discos | ForEach-Object { [string]$_.DriveLetter })
    $i = [array]::IndexOf($letras, [string]$cfg.Disco)
    if ($i -lt 0) { $i = [array]::IndexOf($letras, 'C') }   # el guardado ya no está (desconectado): vuelve a C:
    [math]::Max($i, 0)
}
function Show-Disco {
    $discos = Get-Discos
    if (-not $discos) { return }
    $i = Get-IndiceDisco $discos
    $d = $discos[$i]
    $ui.StatDiskLabel.Text = 'DISCO {0}:' -f $d.DriveLetter
    $ui.StatDiskNav.Text = if ($discos.Count -gt 1) { [string][char]0xE70D } else { '' }   # flechita hacia abajo
    $ui.StatDisk.Text = '{0} GB' -f [math]::Round($d.SizeRemaining / 1GB)
    $ui.StatDiskSub.Text = 'Libres de {0} GB' -f [math]::Round($d.Size / 1GB)
    # menos de 10% libre: en amarillo, como el resto de las alertas
    $ui.StatDisk.Foreground = if ($d.SizeRemaining / $d.Size -lt 0.1) { $Colores.warn } else { $Colores.text }
    $nombre = if ($d.FileSystemLabel) { $d.FileSystemLabel } else { 'Disco local' }
    $ui.DiskCard.ToolTip = if ($discos.Count -gt 1) { "$nombre ($($d.DriveLetter):) · clic para elegir otro disco" } else { "$nombre ($($d.DriveLetter):)" }
    $ui.DiskCard.Cursor = if ($discos.Count -gt 1) { 'Hand' } else { $null }
}
# menú con cada disco: nombre y letra, libres a la derecha y tilde en el que se está viendo
function Show-MenuDiscos {
    $discos = Get-Discos
    if ($discos.Count -lt 2) { return }
    $actual = $discos[(Get-IndiceDisco $discos)].DriveLetter
    $e = @(@{ T = 'head'; Texto = 'DISCOS' })
    foreach ($d in $discos) {
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $libre = New-Object Windows.Controls.TextBlock
        $libre.Text = '{0} GB libres' -f [math]::Round($d.SizeRemaining / 1GB); $libre.FontSize = 11.5; $libre.VerticalAlignment = 'Center'
        $libre.Foreground = if ($d.SizeRemaining / $d.Size -lt 0.1) { $Colores.warn } else { $Colores.muted }
        [void]$sp.Children.Add($libre)
        if ($d.DriveLetter -eq $actual) {
            $ok = New-Object Windows.Controls.TextBlock
            $ok.Text = [char]0xE73E; $ok.FontFamily = 'Segoe MDL2 Assets'; $ok.FontSize = 12; $ok.Foreground = $Colores.accent
            $ok.VerticalAlignment = 'Center'; $ok.Margin = New-Object Windows.Thickness 10, 0, 0, 0
            [void]$sp.Children.Add($ok)
        }
        $nombre = if ($d.FileSystemLabel) { $d.FileSystemLabel } else { 'Disco local' }
        $e += @{ T = 'item'; Texto = "$nombre ($($d.DriveLetter):)"; Der = $sp; A = [scriptblock]::Create("`$cfg.Disco = '$($d.DriveLetter)'; Save-Cfg; Show-Disco") }
    }
    Show-Menu $e
}
$ui.DiskCard.Add_MouseLeftButtonUp({ Show-MenuDiscos })

# ---------- ejecutar acciones en segundo plano ----------
$sync = [hashtable]::Synchronized(@{ Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]' })
$script:Job = $null
$Botones = 'BtnTodo', 'BtnLimpieza', 'BtnJuego', 'BtnRed', 'BtnDiag', 'BtnReparar', 'BtnRestaurar'

function Start-Accion($accion) {
    if ($script:Job) { return }
    $script:AccionActual = $accion
    foreach ($b in $Botones) { $ui[$b].IsEnabled = $false }
    if ($ui.Log.Document.Blocks.Count) { Add-Line '' }
    $ui.Prog.Value = 0; $ui.Pct.Text = '0%'; $ui.Status.Text = 'Arrancando...'
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('Raiz', $Raiz)
    $rs.SessionStateProxy.SetVariable('Simular', [bool]$Simular)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script_ = $Core.ToString() + "`ntry { Invoke-Accion '$accion' } catch { Out-Line ('Error: ' + `$_.Exception.Message) 'err' } finally { `$sync.Q.Enqueue(@{ Tipo = 'done' }) }"
    [void]$ps.AddScript($script_)
    $script:Job = @{ PS = $ps; RS = $rs; H = $ps.BeginInvoke() }
}

function End-Accion {
    if ($script:Job) { try { $script:Job.PS.EndInvoke($script:Job.H) } catch { }; $script:Job.PS.Dispose(); $script:Job.RS.Dispose() }
    $script:Job = $null
    foreach ($b in $Botones) { $ui[$b].IsEnabled = $true }
    $ui.Prog.Value = 100; $ui.Pct.Text = '100%'; $ui.Status.Text = 'Listo'
    Update-Stats
    # la captura espera a que el overlay tenga datos (la saca el timer del overlay)
    if ($Captura) { $script:CapturaLista = Get-Date; return }
    # las del modo juego automático no suenan: pasan con el juego abierto
    if ($script:AccionActual -notin 'autojuego', 'finjuego') { Play-Listo }
}

# ---------- modo juego automático ----------
# Cada 3 s mira si hay un juego de la lista abierto: al abrirlo cierra las apps de fondo y pone energía al
# máximo + Game Bar sin grabar; al cerrarlo (20 s sin el juego) devuelve energía y Game Bar a como estaban.
function Get-JuegoAbierto {
    $nombres = @((Get-Process).ProcessName)
    foreach ($j in @($cfg.Juegos)) { if ($j.P -and @($nombres -like $j.P).Count) { return $j.N } }
    $null
}

function Set-AutoUI {
    $on = [bool]$cfg.AutoJuego
    $ui.AutoToggle.Background = if ($on) { $Colores.accent } else { $Colores.toggleOff }
    $ui.AutoDot.HorizontalAlignment = if ($on) { 'Right' } else { 'Left' }
    $lista = (@($cfg.Juegos) | ForEach-Object { $_.N }) -join ', '
    $ui.AutoSub.Text = if ($script:AutoJuego) { "Activo: $($script:AutoJuego) está abierto" }
                       elseif (-not $lista) { 'Elegí al menos un juego' }
                       elseif ($on) { "Se activa solo al abrir: $lista" }
                       else { "Apagado · juegos: $lista" }
}

function Toggle-Auto {
    $cfg.AutoJuego = -not [bool]$cfg.AutoJuego
    Save-Cfg
    # apagado con un juego abierto: vuelve todo a como estaba
    if (-not $cfg.AutoJuego -and $script:AutoJuego) { $script:AutoJuego = $null; $script:AutoSinJuego = $null; Start-Accion 'finjuego' }
    Set-AutoUI
}

function Check-AutoJuego {
    if ($script:Job) { return }   # hay otra acción corriendo: se revisa en la próxima vuelta
    $j = Get-JuegoAbierto
    if ($j -and -not $script:AutoJuego) {
        $script:AutoJuego = $j; $script:AutoSinJuego = $null
        Start-Accion 'autojuego'
        $tray.ShowBalloonTip(4000, "Modo juego: $j", 'Cerré las apps de fondo y puse la energía al máximo. Al salir del juego vuelve a como estaba.', 'Info')
        Set-AutoUI
    } elseif (-not $j -and $script:AutoJuego) {
        # unos segundos de gracia: FiveM reinicia el proceso del juego al entrar a un server
        if (-not $script:AutoSinJuego) { $script:AutoSinJuego = Get-Date; return }
        if (((Get-Date) - $script:AutoSinJuego).TotalSeconds -lt 20) { return }
        $fin = $script:AutoJuego; $script:AutoJuego = $null; $script:AutoSinJuego = $null
        Start-Accion 'finjuego'
        $tray.ShowBalloonTip(4000, "Saliste de $fin", 'La energía y la Game Bar volvieron a como estaban.', 'Info')
        Set-AutoUI
    } elseif ($j) { $script:AutoSinJuego = $null }
}

# menú para elegir juegos: los de la lista (tocar = sacar) y los programas abiertos con ventana (tocar = agregar)
function Show-MenuJuegos {
    $e = @(@{ T = 'head'; Texto = 'JUEGOS · tocá uno para sacarlo' })
    foreach ($j in @($cfg.Juegos)) {
        $e += @{ T = 'item'; Texto = $j.N; Der = (New-Toggle $true); A = [scriptblock]::Create("Quitar-Juego '$($j.P -replace "'", "''")'") }
    }
    if (-not @($cfg.Juegos).Count) { $e += @{ T = 'info'; Texto = 'No hay juegos en la lista' } }
    $ignorar = 'explorer', 'ApplicationFrameHost', 'TextInputHost', 'SystemSettings', 'ShellExperienceHost', 'SearchHost', 'StartMenuExperienceHost', 'LockApp'
    $abiertos = @(Get-Process | Where-Object {
        $p = $_
        $_.MainWindowHandle -ne 0 -and $_.Id -ne $PID -and $ignorar -notcontains $_.ProcessName -and
        -not (@($cfg.Juegos) | Where-Object { $p.ProcessName -like $_.P })
    } | Sort-Object ProcessName -Unique)
    $e += @{ T = 'sep' }
    $e += @{ T = 'head'; Texto = 'AGREGAR · programas abiertos' }
    if ($abiertos) {
        foreach ($p in $abiertos) {
            $nombre = if ($p.Description) { $p.Description } else { $p.ProcessName }
            $e += @{ T = 'item'; Texto = $nombre; A = [scriptblock]::Create("Agregar-Juego '$($nombre -replace "'", "''")' '$($p.ProcessName -replace "'", "''")'") }
        }
    } else { $e += @{ T = 'info'; Texto = 'Abrí el juego y volvé acá para agregarlo' } }
    Show-Menu $e
}
function Agregar-Juego($nombre, $proceso) { $cfg.Juegos = @($cfg.Juegos) + @(@{ N = $nombre; P = $proceso }); Save-Cfg; Set-AutoUI }
function Quitar-Juego($proceso) { $cfg.Juegos = @(@($cfg.Juegos) | Where-Object { $_.P -ne $proceso }); Save-Cfg; Set-AutoUI }

$ui.AutoToggle.Add_MouseLeftButtonUp({ Toggle-Auto })
$ui.AutoJuegosLink.Add_MouseLeftButtonUp({ Show-MenuJuegos })

# Sonido de "listo": dos notas que suben (La5 → Mi6), suaves y cortas, generadas acá (sin archivos).
# Cada nota: seno + un poco de octava arriba (brillo tipo cristal), ataque de 6 ms y cola que se apaga sola.
function New-SonidoListo {
    $hz = 44100; $dur = 0.55; $n = [int]($hz * $dur)
    $notas = @(@{ F = 880.0; T0 = 0.0; Vol = 0.20 }, @{ F = 1318.5; T0 = 0.085; Vol = 0.24 })
    $pcm = New-Object byte[] ($n * 2)
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / $hz; $s = 0.0
        foreach ($o in $notas) {
            $u = $t - $o.T0
            if ($u -lt 0) { continue }
            $env = [math]::Min(1, $u / 0.006) * [math]::Exp(-$u * 9)
            $w = 2 * [math]::PI * $o.F * $u
            $s += $o.Vol * $env * ([math]::Sin($w) + 0.18 * [math]::Sin(2 * $w))
        }
        $v = [int16][math]::Max(-32767, [math]::Min(32767, $s * 32767))
        $pcm[2 * $i] = $v -band 0xFF; $pcm[2 * $i + 1] = ($v -shr 8) -band 0xFF
    }
    # encabezado WAV: PCM 16 bits mono
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $pcm.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$hz); $w.Write([int]($hz * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$pcm.Length); $w.Write($pcm)
    $w.Flush(); $ms.Position = 0
    $p = New-Object Media.SoundPlayer $ms; $p.Load(); $p
}
function Play-Listo {
    try {
        if (-not $script:SonidoListo) { $script:SonidoListo = New-SonidoListo }   # se arma una vez y queda en memoria
        $script:SonidoListo.Play()
    } catch { }
}

function Save-Captura {
    $win.UpdateLayout()
    $w = [int]$ui.Root.ActualWidth; $h = [int]$ui.Root.ActualHeight
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($ui.Root)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($Captura); $enc.Save($fs); $fs.Close()
    # también el overlay, al lado: captura_overlay.png
    if ($ov.IsVisible) {
        $ov.UpdateLayout()
        $bo = $ovUi.Box
        $bmp2 = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$bo.ActualWidth), ([int]$bo.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp2.Render($bo)
        $enc2 = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc2.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp2))
        $fs2 = [IO.File]::Create(($Captura -replace '\.png$', '_overlay.png')); $enc2.Save($fs2); $fs2.Close()
        $exOv = [JVps.Shell]::GetWindowLong((New-Object Windows.Interop.WindowInteropHelper $ov).Handle, -20)
        Set-Content ($Captura -replace '\.png$', '_estilos.txt') ("overlay toolwindow={0} noactivate={1} atajo={2}" -f [bool]($exOv -band 0x80), [bool]($exOv -band 0x08000000), $atajo.Registrado)
    }
    # y el menú de elegir datos: captura_menu.png
    Show-MenuDatos
    $menuWin.UpdateLayout()
    $bmp3 = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$menuWin.ActualWidth), ([int]$menuWin.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp3.Render($menuWin.Content)
    $enc3 = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc3.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp3))
    $fs3 = [IO.File]::Create(($Captura -replace '\.png$', '_menu.png')); $enc3.Save($fs3); $fs3.Close()
    $menuWin.Hide()
    # y un cartel de ejemplo: captura_dialogo.png
    $dd = New-Dialogo '¿Abrir siempre sin pedir permisos?' (Texto-Instalar) 'Instalar' 'Ahora no' 'escudo'
    $dd.Show(); $dd.UpdateLayout()
    $bmp4 = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$dd.ActualWidth), ([int]$dd.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp4.Render($dd.Content)
    $enc4 = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc4.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp4))
    $fs4 = [IO.File]::Create(($Captura -replace '\.png$', '_dialogo.png')); $enc4.Save($fs4); $fs4.Close()
    $dd.Close()
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(80)
$timer.Add_Tick({
    $m = $null
    while ($sync.Q.TryDequeue([ref]$m)) {
        switch ($m.Tipo) {
            'line' { Add-Line $m.T $m.K }
            'prog' { $ui.Prog.Value = $m.P; $ui.Pct.Text = "$($m.P)%"; $ui.Status.Text = $m.L }
            'done' { End-Accion }
            'update' { Handle-Update $m }
            'updprog' { Handle-UpdProgreso $m }
            'upddl' { Finish-Update $m }
        }
    }
    # actualizando: cuando la versión nueva avisa que abrió (o a los 30 s) se cierra esta
    if ($script:UpdEsperaHasta -and ($script:EvtListo.WaitOne(0) -or (Get-Date) -ge $script:UpdEsperaHasta)) {
        $script:UpdEsperaHasta = $null
        Close-UpdDialogo
        Salir
    }
})
$timer.Start()

# ---------- eventos ----------
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnClose.Add_Click({ Hide-Main })
$ui.BtnOverlay.Add_Click({ Set-Overlay (-not $ov.IsVisible) })
$ui.BtnTema.Add_Click({ Show-MenuTemas })
# con una versión nueva ya encontrada, los dos abren el cartel; si no, busca a mano
$ui.UpdPill.Add_Click({ Ofrecer-Update })
$ui.BtnUpdate.Add_Click({ if ($script:UpdPendiente) { Ofrecer-Update } else { Start-BuscarUpdate $true } })
$ui.BtnRed.Add_Click({
    $ok = Show-Dialogo 'Red' "Mide tu conexión, te dice dónde están los picos (Wi-Fi, cable o proveedor) y aplica ajustes seguros: autoajuste de TCP, ahorro de energía de la placa, límite de red con multimedia, Windows Update sin subir a otras PCs y paquetes sin demora.`n`nNo cambia DNS ni IP. Antes crea un punto de restauración de Windows, guarda cómo estaba todo y 'Restaurar ajustes' lo deja igual.`n`nLa conexión se corta unos segundos al final." 'Arrancar' 'Cancelar' 'pregunta'
    if ($ok) { Start-Accion 'red' }
})
$ui.BtnRestaurar.Add_Click({
    $red = Test-Path -LiteralPath (Join-Path $Raiz 'red_respaldo.json')
    $juego = Test-Path -LiteralPath (Join-Path $Raiz 'juego_respaldo.json')
    if (-not $red -and -not $juego) {
        Show-Dialogo 'Restaurar ajustes' 'No hay nada para restaurar: todo está como lo dejó Windows.' 'OK' '' 'info' | Out-Null; return
    }
    $que = @(); if ($red) { $que += '•  Red: todo como estaba antes de los ajustes (la conexión se corta unos segundos)' }
    if ($juego) { $que += '•  Plan de energía y Game Bar: como estaban antes de "Todo para jugar"' }
    $ok = Show-Dialogo 'Restaurar ajustes' ("Vuelve a como estaba:`n`n" + ($que -join "`n")) 'Restaurar' 'Cancelar' 'alerta'
    if ($ok) { Start-Accion 'restaurar' }
})
$ui.BtnTodo.Add_Click({ Start-Accion 'todo' })
$ui.BtnLimpieza.Add_Click({ Start-Accion 'limpieza' })
$ui.BtnJuego.Add_Click({ Start-Accion 'juego' })
$ui.BtnDiag.Add_Click({ Start-Accion 'diagnostico' })
$ui.BtnReparar.Add_Click({
    $ok = Show-Dialogo 'Reparar Windows' "Revisa los archivos de Windows y arregla los dañados. Tarda entre 10 y 30 minutos.`n`nSi la PC tiene pantallazos azules, primero arreglá eso (suele ser la RAM) y después reparás." 'Arrancar' 'Cancelar' 'alerta'
    if ($ok) { Start-Accion 'reparar' }
})
$ui.InfoLink.Add_MouseLeftButtonUp({
    $txt = @"
TODO PARA JUGAR
Deja la PC lista: Limpieza + Modo juego + plan de energía en Alto rendimiento + la Game Bar sin grabar de fondo (eso cuesta FPS). El plan y la Game Bar vuelven a como estaban al cerrar el optimizador o con "Restaurar ajustes".

MODO JUEGO AUTOMÁTICO
Con el interruptor prendido, al abrir un juego de la lista (FiveM y GTA V vienen puestos) cierra las apps de fondo y pone la energía al máximo con la Game Bar sin grabar, y te avisa. Al cerrar el juego, energía y Game Bar vuelven a como estaban. En "Elegir juegos" sacás o agregás juegos: abrí el juego y aparece en la lista para sumarlo. Funciona aunque el optimizador esté en la bandeja.

LIMPIEZA
Borra temporales, caché de miniaturas, descargas viejas de Windows Update, reportes de errores, caché de Discord y FiveM, logs de Steam y la caché de DNS. Te dice cuánto liberó.

MODO JUEGO
Cierra programas de fondo (OneDrive, Widgets, Epic, EA, BlueStacks, Adobe, Autodesk, Gaijin, uTorrent). Vuelven a abrirse solos al reiniciar. No toca Steam, Discord, navegadores ni anticheats.

RED
Mide el ping al router y a internet para saber si los picos vienen del Wi-Fi, del cable o del proveedor, y avisa si el cable va a 100 Mbps en una placa Gigabit. Después aplica ajustes seguros: autoajuste de TCP en normal, apaga el ahorro de energía de la placa, saca el límite de red con multimedia, Windows Update deja de subir a PCs de desconocidos y los paquetes chicos salen sin demora. Mide de nuevo y compara. Si la conexión no vuelve, deshace todo solo.

RESTAURAR AJUSTES
Deja la red, el plan de energía y la Game Bar exactamente como estaban antes (se guarda un respaldo la primera vez).

DIAGNÓSTICO
Velocidad de la RAM (y si va más lenta de lo que da: XMP/EXPO), pantallazos azules de la última semana explicados con qué probar primero, espacio y salud de los discos, programas de arranque y driver de video.

REPARAR WINDOWS
DISM + SFC: revisa los archivos de Windows y arregla los dañados. Tarda 10 a 30 minutos.

PUNTO DE RESTAURACIÓN
Antes de Red y de Reparar Windows se crea un punto de restauración de Windows (si Windows ya hizo uno hoy, usa ese).

QUÉ NO HACE
No borra fotos, documentos, descargas ni la Papelera. No toca servicios ni el BIOS, y en el registro solo cambia los ajustes de Red (con respaldo). No cambia tu DNS ni tu IP. No manda datos a ningún lado (solo hace un ping a 1.1.1.1 para medir tu latencia en pantalla y una vez por día se fija en GitHub si hay versión nueva).

DATOS EN PANTALLA
Ctrl+Shift+O los muestra u oculta desde cualquier lado, incluso jugando. También el botón del monitor (arriba) o click derecho en la paloma de la bandeja. Se pueden arrastrar, y con click derecho elegís la esquina. Se ven en juegos en ventana o pantalla completa sin bordes.

AL CERRAR
La X no cierra: lo deja en la bandeja, al lado del reloj. Para cerrarlo del todo: click derecho en la paloma > Salir.
"@
    Show-Dialogo '¿Qué hace cada botón?' $txt.Trim() 'Entendido' '' 'info' | Out-Null
})
$ui.LogLink.Add_MouseLeftButtonUp({
    $dir = Join-Path $Raiz 'logs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Start-Process explorer.exe $dir
})

# ================================
# DATOS EN PANTALLA (overlay)
# ================================

[xml]$ovXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="L" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,0,5,0"/>
    </Style>
    <Style x:Key="V" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,0,14,0"/>
    </Style>
  </Window.Resources>
  <Border x:Name="Box" CornerRadius="12" Background="{DynamicResource OvBg}" BorderBrush="{DynamicResource AccentLine}" BorderThickness="1" Padding="10,7,0,7" Cursor="SizeAll">
    <StackPanel Orientation="Horizontal">
      <Ellipse x:Name="OvLogo" Width="20" Height="20" Margin="0,0,12,0" VerticalAlignment="Center" Fill="{DynamicResource Accent}"/>
      <!-- cada dato en su grupo (Grp*) para poder ocultarlo desde "Elegir datos" -->
      <StackPanel x:Name="GrpCpu" Orientation="Horizontal"><TextBlock Text="CPU" Style="{StaticResource L}"/><TextBlock x:Name="OvCpu" Text="-" Style="{StaticResource V}"/></StackPanel>
      <StackPanel x:Name="GrpRam" Orientation="Horizontal"><TextBlock Text="RAM" Style="{StaticResource L}"/><TextBlock x:Name="OvRam" Text="-" Style="{StaticResource V}"/></StackPanel>
      <StackPanel x:Name="GrpGpu" Orientation="Horizontal"><TextBlock Text="GPU" Style="{StaticResource L}"/><TextBlock x:Name="OvGpu" Text="-" Style="{StaticResource V}"/></StackPanel>
      <StackPanel x:Name="GrpTemp" Orientation="Horizontal"><TextBlock Text="TEMP" Style="{StaticResource L}"/><TextBlock x:Name="OvTemp" Text="-" Style="{StaticResource V}"/></StackPanel>
      <StackPanel x:Name="GrpVram" Orientation="Horizontal"><TextBlock Text="VRAM" Style="{StaticResource L}"/><TextBlock x:Name="OvVram" Text="-" Style="{StaticResource V}"/></StackPanel>
      <StackPanel x:Name="GrpPing" Orientation="Horizontal"><TextBlock Text="PING" Style="{StaticResource L}"/><TextBlock x:Name="OvPing" Text="-" Style="{StaticResource V}"/></StackPanel>
      <TextBlock x:Name="OvHora" Text="--:--" Style="{StaticResource V}" Foreground="{DynamicResource Accent2}"/>
    </StackPanel>
  </Border>
</Window>
'@

$ov = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $ovXaml))
Set-VentanaHerramienta $ov $true
$ovUi = @{}
foreach ($n in 'Box', 'OvLogo', 'OvCpu', 'OvRam', 'OvGpu', 'OvTemp', 'OvVram', 'OvPing', 'OvHora', 'GrpCpu', 'GrpRam', 'GrpGpu', 'GrpTemp', 'GrpVram', 'GrpPing') { $ovUi[$n] = $ov.FindName($n) }

# datos elegibles: clave -> [nombre en el menú, elemento del overlay, ¿necesita NVIDIA?]
$Datos = [ordered]@{
    logo = @('Paloma',            'OvLogo',  $false)
    cpu  = @('CPU',               'GrpCpu',  $false)
    ram  = @('RAM',               'GrpRam',  $false)
    gpu  = @('Uso de GPU',        'GrpGpu',  $true)
    temp = @('Temperatura de GPU', 'GrpTemp', $true)
    vram = @('VRAM',              'GrpVram', $true)
    ping = @('Ping',              'GrpPing', $false)
    hora = @('Hora',              'OvHora',  $false)
}
function Apply-Datos {
    foreach ($k in $Datos.Keys) {
        $d = $Datos[$k]
        $ver = ($cfg.Datos -contains $k) -and (-not $d[2] -or $stats.HayGpu -ne $false)
        $ovUi[$d[1]].Visibility = if ($ver) { 'Visible' } else { 'Collapsed' }
    }
}
function Toggle-Dato($k) {
    if ($cfg.Datos -contains $k) {
        if (@($cfg.Datos).Count -le 1) { return }   # no dejar el cartelito vacío
        $cfg.Datos = @($cfg.Datos | Where-Object { $_ -ne $k })
    } else {
        $cfg.Datos = @($Datos.Keys | Where-Object { $_ -eq $k -or $cfg.Datos -contains $_ })   # mantiene el orden
    }
    Apply-Datos
    Save-Cfg
}
function Show-MenuDatos {
    $e = @(@{ T = 'head'; Texto = 'MOSTRAR EN PANTALLA' })
    foreach ($k in $Datos.Keys) {
        $nombre = $Datos[$k][0]
        if ($Datos[$k][2] -and $stats.HayGpu -eq $false) { $nombre += '  (solo NVIDIA)' }
        $e += @{ T = 'check'; Texto = $nombre; Clave = $k }
    }
    Show-Menu $e
}
if ($logo) { $b = New-Object Windows.Media.ImageBrush $logo; $b.Stretch = 'UniformToFill'; $ovUi.OvLogo.Fill = $b }

# ---------- configuración guardada (visible, esquina, posición a mano) ----------
$cfgPath = Join-Path $Raiz 'config.json'
$cfg = @{ Overlay = $false; Pos = 'TR'; Left = 0; Top = 0; Tema = 'Esmeralda'; Claro = $false
          Datos = @('logo', 'cpu', 'ram', 'gpu', 'temp', 'vram', 'ping', 'hora')
          # modo juego automático: N = nombre que se muestra, P = nombre del proceso (acepta *)
          # FiveM: el que importa es el proceso del juego (FiveM_b3258_GTAProcess), no el launcher
          AutoJuego = $false; Juegos = @(@{ N = 'FiveM'; P = 'FiveM_*GTAProcess' }, @{ N = 'GTA V'; P = 'GTA5' }) }
if (Test-Path $cfgPath) {
    $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
    foreach ($k in 'Overlay', 'Pos', 'Left', 'Top', 'Tema', 'Claro', 'Datos', 'NoInstalar', 'Disco', 'AutoJuego', 'Juegos') { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } }
}
function Save-Cfg {
    if ($Captura) { return }   # las capturas de prueba no tocan tu configuración
    if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
    $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
}

function Set-OvPos($pos) {
    $cfg.Pos = $pos
    $wa = [Windows.SystemParameters]::WorkArea
    $ov.UpdateLayout()
    $w = $ov.ActualWidth; $h = $ov.ActualHeight; $m = 14
    switch ($pos) {
        'TL' { $ov.Left = $wa.Left + $m;             $ov.Top = $wa.Top + $m }
        'TR' { $ov.Left = $wa.Right - $w - $m;       $ov.Top = $wa.Top + $m }
        'BL' { $ov.Left = $wa.Left + $m;             $ov.Top = $wa.Bottom - $h - $m }
        'BR' { $ov.Left = $wa.Right - $w - $m;       $ov.Top = $wa.Bottom - $h - $m }
        'Custom' { $ov.Left = $cfg.Left;             $ov.Top = $cfg.Top }
    }
    Save-Cfg
}

# se arrastra con click izquierdo
$ovUi.Box.Add_MouseLeftButtonDown({
    $ov.DragMove()
    $cfg.Left = $ov.Left; $cfg.Top = $ov.Top; $cfg.Pos = 'Custom'; Save-Cfg
})
# al cambiar de ancho (ej: aparece la GPU) se reacomoda en su esquina
$ov.Add_SizeChanged({ if ($cfg.Pos -ne 'Custom') { Set-OvPos $cfg.Pos } })

# click derecho en el overlay: el mismo menú oscuro que la bandeja (ver MENU más abajo)
$ovUi.Box.Add_MouseRightButtonUp({
    Show-Menu @(
        @{ T = 'item'; Texto = 'Ocultar datos'; A = { Set-Overlay $false } }
        @{ T = 'item'; Texto = 'Elegir qué datos mostrar'; A = { Show-MenuDatos } }
        @{ T = 'sep' }
        @{ T = 'head'; Texto = 'ESQUINA' }
        @{ T = 'item'; Texto = 'Arriba a la izquierda'; A = { Set-OvPos 'TL' } }
        @{ T = 'item'; Texto = 'Arriba a la derecha';   A = { Set-OvPos 'TR' } }
        @{ T = 'item'; Texto = 'Abajo a la izquierda';  A = { Set-OvPos 'BL' } }
        @{ T = 'item'; Texto = 'Abajo a la derecha';    A = { Set-OvPos 'BR' } }
        @{ T = 'sep' }
        @{ T = 'item'; Texto = 'Abrir Optimizador'; A = { Show-Main } }
    )
})

# ---------- recolector de datos en segundo plano ----------
$stats = [hashtable]::Synchronized(@{ Run = $true; Visible = $false })
$rsC = [runspacefactory]::CreateRunspace(); $rsC.Open()
$rsC.SessionStateProxy.SetVariable('stats', $stats)
$psC = [powershell]::Create(); $psC.Runspace = $rsC
[void]$psC.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'
    # CPU con GetSystemTimes: instantáneo y no depende del idioma de Windows
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class CpuMeter {
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    static long pi, pk, pu;
    public static double Sample() {
        long i, k, u; GetSystemTimes(out i, out k, out u);
        long di = i - pi, dk = k - pk, du = u - pu; pi = i; pk = k; pu = u;
        long tot = dk + du; return tot > 0 ? (tot - di) * 100.0 / tot : 0;
    }
}
'@
    $smi = (Get-Command nvidia-smi).Source
    $stats.HayGpu = [bool]$smi
    $ping = New-Object Net.NetworkInformation.Ping
    [void][CpuMeter]::Sample()
    $n = 0
    while ($stats.Run) {
        Start-Sleep -Milliseconds 1000
        if (-not $stats.Visible) { continue }
        $stats.Cpu = [math]::Round([CpuMeter]::Sample())
        $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
        $stats.RamUsada = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        $stats.RamTotal = $os.TotalVisibleMemorySize / 1MB
        if ($smi) {
            $o = & $smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits | Select-Object -First 1
            if ($o) {
                $p = $o -split ',\s*'
                $stats.Gpu = [int]$p[0]; $stats.GpuTemp = [int]$p[1]
                $stats.Vram = [double]$p[2] / 1024; $stats.VramTotal = [double]$p[3] / 1024
            }
        }
        if ($n % 2 -eq 0) {
            try { $r = $ping.Send('1.1.1.1', 800); $stats.Ping = if ($r.Status -eq 'Success') { [int]$r.RoundtripTime } else { -1 } } catch { $stats.Ping = -1 }
        }
        $n++; $stats.Tick = $n
    }
})
$hC = $psC.BeginInvoke()

function Color-Por($v, $amarillo, $rojo) {
    if ($v -ge $rojo) { $Colores.err } elseif ($v -ge $amarillo) { $Colores.warn } else { $Colores.text }
}
function Update-Overlay {
    $ovUi.OvHora.Text = (Get-Date -Format 'HH:mm')
    Apply-Datos
    if (-not $stats.Tick) { return }
    $ovUi.OvCpu.Text = "$($stats.Cpu)%"; $ovUi.OvCpu.Foreground = Color-Por $stats.Cpu 70 90
    $pctRam = $stats.RamUsada * 100 / $stats.RamTotal
    $ovUi.OvRam.Text = '{0:N1}/{1:N0} GB' -f $stats.RamUsada, $stats.RamTotal; $ovUi.OvRam.Foreground = Color-Por $pctRam 75 90
    if ($stats.HayGpu) {
        $ovUi.OvGpu.Text = "$($stats.Gpu)%"; $ovUi.OvGpu.Foreground = Color-Por $stats.Gpu 85 98
        $ovUi.OvTemp.Text = "$($stats.GpuTemp)°C"; $ovUi.OvTemp.Foreground = Color-Por $stats.GpuTemp 75 83
        $ovUi.OvVram.Text = '{0:N1}/{1:N0} GB' -f $stats.Vram, $stats.VramTotal
        $ovUi.OvVram.Foreground = Color-Por ($stats.Vram * 100 / [math]::Max(1, $stats.VramTotal)) 85 95
    }
    if ($stats.Ping -lt 0) { $ovUi.OvPing.Text = 'sin red'; $ovUi.OvPing.Foreground = $Colores.err }
    elseif ($null -ne $stats.Ping) { $ovUi.OvPing.Text = "$($stats.Ping) ms"; $ovUi.OvPing.Foreground = Color-Por $stats.Ping 60 120 }
}

function Set-Overlay([bool]$mostrar) {
    $stats.Visible = $mostrar
    $cfg.Overlay = $mostrar
    if ($mostrar) { $ov.Show(); Set-OvPos $cfg.Pos; Update-Overlay } else { $ov.Hide() }
    $ui.BtnOverlay.Foreground = if ($mostrar) { $Colores.accent } else { $Colores.muted }
    Save-Cfg
}

# ================================
# BANDEJA (al lado del reloj)
# ================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ---------- atajo global Ctrl+Shift+O (anda aunque estés en un juego) ----------
# Una ventana invisible de Windows recibe el aviso de RegisterHotKey y dispara el evento Pressed.
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class AtajoGlobal : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public event EventHandler Pressed;
    public bool Registrado;
    public AtajoGlobal(uint mods, uint vk) {
        CreateHandle(new CreateParams());
        Registrado = RegisterHotKey(Handle, 1, mods | 0x4000, vk);   // 0x4000 = no repetir si se mantiene apretado
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);   // WM_HOTKEY
        base.WndProc(ref m);
    }
    public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}
'@
$AtajoTexto = 'Ctrl+Shift+O'
$atajo = New-Object AtajoGlobal 6, 0x4F   # 2 = Ctrl, 4 = Shift; 0x4F = tecla O
$atajo.add_Pressed({ Set-Overlay (-not $ov.IsVisible) })
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Text = 'Optimizador J.vps'
try {
    $bmpT = New-Object Drawing.Bitmap ([Drawing.Bitmap]::FromStream((New-Object IO.MemoryStream (, [Convert]::FromBase64String($LogoB64))))), 32, 32
    $tray.Icon = [Drawing.Icon]::FromHandle($bmpT.GetHicon())
} catch { $tray.Icon = [Drawing.SystemIcons]::Application }

function Get-TrayMenu {
    $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $ram = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100 / $os.TotalVisibleMemorySize)
    @(
        @{ T = 'item'; Texto = 'Abrir Optimizador'; A = { Show-Main } }
        @{ T = 'sep' }
        @{ T = 'info'; Texto = "Optimizador J.vps  ·  v$Version" }
        @{ T = 'info'; Texto = "RAM en uso: $ram%" }
        @{ T = 'info'; Texto = $(if ($atajo.Registrado) { "Atajo de los datos: $AtajoTexto" } else { "Atajo $AtajoTexto ocupado por otro programa" }) }
        @{ T = 'sep' }
        @{ T = 'toggle'; Texto = 'Datos en pantalla'; On = $ov.IsVisible; A = { Set-Overlay (-not $ov.IsVisible) } }
        @{ T = 'item'; Texto = 'Elegir qué datos mostrar'; A = { Show-MenuDatos } }
        @{ T = 'sep' }
        @{ T = 'toggle'; Texto = 'Modo juego automático'; On = [bool]$cfg.AutoJuego; A = { Toggle-Auto } }
        @{ T = 'sep' }
        @{ T = 'item'; Texto = 'Buscar actualizaciones'; A = { Start-BuscarUpdate $true } }
        @{ T = 'item'; Texto = 'Salir'; A = { Salir } }
    )
}
$tray.Add_MouseUp({
    if ($_.Button -eq 'Left') { Show-Main }
    elseif ($_.Button -eq 'Right') { Show-Menu (Get-TrayMenu) }
})
$tray.Visible = $true

# ================================
# MENU (oscuro y redondeado, para la bandeja y el overlay)
# ================================

[xml]$menuXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize" FontFamily="Segoe UI">
  <Border x:Name="MBox" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="14" CornerRadius="10"
          Background="{DynamicResource MenuBg}" BorderBrush="{DynamicResource MenuLine}" BorderThickness="1" Padding="5">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="4" Opacity="0.55" Color="Black"/></Border.Effect>
    <StackPanel x:Name="MItems" MinWidth="220"/>
  </Border>
</Window>
'@
$menuWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $menuXaml))
Set-VentanaHerramienta $menuWin $false
$mBox = $menuWin.FindName('MBox'); $mItems = $menuWin.FindName('MItems')
$menuWin.Add_Deactivated({ $menuWin.Hide() })
$menuWin.Add_KeyDown({ if ($_.Key -eq 'Escape') { $menuWin.Hide() } })

function New-MenuRow($texto, $accion, $derecha) {
    $row = New-Object Windows.Controls.Border
    $row.Padding = New-Object Windows.Thickness 12, 8, 12, 8
    $row.CornerRadius = New-Object Windows.CornerRadius 6
    $row.Background = [Windows.Media.Brushes]::Transparent
    $row.Cursor = 'Hand'
    $g = New-Object Windows.Controls.Grid
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'; [void]$g.ColumnDefinitions.Add($c2)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $texto; $tb.FontSize = 13; $tb.Foreground = $Colores.text; $tb.VerticalAlignment = 'Center'
    [void]$g.Children.Add($tb)
    if ($derecha) { [Windows.Controls.Grid]::SetColumn($derecha, 1); $derecha.Margin = New-Object Windows.Thickness 16, 0, 0, 0; [void]$g.Children.Add($derecha) }
    $row.Child = $g
    $row.Tag = $accion
    $row.Add_MouseEnter({ $this.Background = $Colores.hover })
    $row.Add_MouseLeave({ $this.Background = [Windows.Media.Brushes]::Transparent })
    $row.Add_MouseLeftButtonUp({
        $a = $this.Tag
        if ($a -is [hashtable]) {
            # fila de "Elegir datos": cambia el dato y el interruptor sin cerrar el menú, para tildar varios seguidos
            Toggle-Dato $a.Clave
            $g = $this.Child; $g.Children.RemoveAt(1)
            $nuevo = New-Toggle ($cfg.Datos -contains $a.Clave)
            [Windows.Controls.Grid]::SetColumn($nuevo, 1); $nuevo.Margin = New-Object Windows.Thickness 16, 0, 0, 0
            [void]$g.Children.Add($nuevo)
            return
        }
        $menuWin.Hide(); if ($a) { & $a }
    })
    $row
}

function New-Toggle([bool]$on) {
    # interruptor tipo pastilla: verde con la bolita a la derecha si está prendido
    $t = New-Object Windows.Controls.Border
    $t.Width = 34; $t.Height = 18; $t.CornerRadius = New-Object Windows.CornerRadius 9
    $t.Background = if ($on) { $Colores.accent } else { $Colores.toggleOff }
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 12; $dot.Height = 12; $dot.Fill = [Windows.Media.Brushes]::White
    $dot.HorizontalAlignment = if ($on) { 'Right' } else { 'Left' }
    $dot.Margin = New-Object Windows.Thickness 3, 0, 3, 0
    $t.Child = $dot
    $t
}

function Show-Menu($entradas) {
    $mItems.Children.Clear()
    foreach ($e in $entradas) {
        switch ($e.T) {
            'item'   { [void]$mItems.Children.Add((New-MenuRow $e.Texto $e.A $e.Der)) }
            'toggle' { [void]$mItems.Children.Add((New-MenuRow $e.Texto $e.A (New-Toggle $e.On))) }
            'check'  { [void]$mItems.Children.Add((New-MenuRow $e.Texto @{ Clave = $e.Clave } (New-Toggle ($cfg.Datos -contains $e.Clave)))) }
            'info' {
                $tb = New-Object Windows.Controls.TextBlock
                $tb.Text = $e.Texto; $tb.FontSize = 12.5; $tb.Foreground = $Colores.muted
                $tb.Margin = New-Object Windows.Thickness 12, 5, 12, 5
                [void]$mItems.Children.Add($tb)
            }
            'head' {
                $tb = New-Object Windows.Controls.TextBlock
                $tb.Text = $e.Texto; $tb.FontSize = 10; $tb.FontWeight = 'Bold'; $tb.Foreground = $Colores.muted
                $tb.Margin = New-Object Windows.Thickness 12, 6, 12, 3
                [void]$mItems.Children.Add($tb)
            }
            'sep' {
                $s = New-Object Windows.Controls.Border
                $s.Height = 1; $s.Background = $Colores.menuLine
                $s.Margin = New-Object Windows.Thickness 6, 5, 6, 5
                [void]$mItems.Children.Add($s)
            }
        }
    }
    # posición: al lado del mouse, sin salirse de la pantalla (convierte píxeles a unidades de WPF por el zoom de Windows)
    $px = [Windows.Forms.Cursor]::Position
    $pt = New-Object Windows.Point $px.X, $px.Y
    $src = [Windows.PresentationSource]::FromVisual($win)
    if ($src) { $pt = $src.CompositionTarget.TransformFromDevice.Transform($pt) }
    $menuWin.Left = -9999; $menuWin.Top = -9999
    $menuWin.Show(); $menuWin.UpdateLayout()
    $w = $menuWin.ActualWidth; $h = $menuWin.ActualHeight; $wa = [Windows.SystemParameters]::WorkArea
    $x = $pt.X - $w + 14; $y = $pt.Y - $h + 14
    if ($x -lt $wa.Left) { $x = $pt.X - 14 }
    if ($y -lt $wa.Top) { $y = $pt.Y - 14 }
    $menuWin.Left = [math]::Min($x, $wa.Right - $w); $menuWin.Top = [math]::Min($y, $wa.Bottom - $h)
    $menuWin.Activate() | Out-Null
    [void][JVps.Shell]::SetForegroundWindow((New-Object Windows.Interop.WindowInteropHelper $menuWin).Handle)
}

$script:AvisoBandeja = $false
function Show-Main {
    $win.Show()
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
    $win.Activate() | Out-Null
}
function Hide-Main {
    $win.Hide()
    if (-not $script:AvisoBandeja) {
        $script:AvisoBandeja = $true
        $tray.ShowBalloonTip(4000, 'Sigue abierto', 'El Optimizador quedó en la bandeja, al lado del reloj. Click derecho en la paloma para mostrar u ocultar los datos en pantalla, o Salir.', 'Info')
    }
}
$script:Saliendo = $false
function Salir {
    $script:Saliendo = $true
    $stats.Run = $false
    if ($script:Job) { try { $script:Job.PS.Stop() } catch { } }
    # plan de energía y Game Bar vuelven a como estaban antes de "Todo para jugar"
    # (el núcleo se carga acá adentro, así sus funciones no pisan las de la ventana)
    # (al cerrarse para actualizar no: la versión nueva sigue con los ajustes puestos)
    if (-not $script:Actualizando -and (Test-Path -LiteralPath (Join-Path $Raiz 'juego_respaldo.json'))) {
        try { . $Core; [void](Restaurar-Juego) } catch { }
    }
    $tray.Visible = $false; $tray.Dispose()
    $atajo.Dispose()
    $ov.Close(); $win.Close()
    $app.Shutdown()
}

# si se abre el .bat de nuevo, la otra instancia avisa por este evento y acá se muestra la ventana
if ($script:Mutex) {
    $sec = New-Object Security.AccessControl.EventWaitHandleSecurity
    $todos = New-Object Security.Principal.SecurityIdentifier ([Security.Principal.WellKnownSidType]::WorldSid), $null
    $sec.AddAccessRule((New-Object Security.AccessControl.EventWaitHandleAccessRule $todos, ([Security.AccessControl.EventWaitHandleRights]'Synchronize, Modify'), 'Allow'))
    $nuevo = $false
    $script:EvtMostrar = New-Object Threading.EventWaitHandle $false, ([Threading.EventResetMode]::AutoReset), 'Local\OptimizadorJvps_Mostrar', ([ref]$nuevo), $sec
}

$timerOv = New-Object Windows.Threading.DispatcherTimer
$timerOv.Interval = [TimeSpan]::FromMilliseconds(1000)
$timerOv.Add_Tick({
    if ($ov.IsVisible) { Update-Overlay }
    if ($script:CapturaLista -and ($stats.Tick -ge 3 -or ((Get-Date) - $script:CapturaLista).TotalSeconds -gt 20)) {
        $script:CapturaLista = $null; Save-Captura; Salir; return
    }
    if ($script:EvtMostrar -and $script:EvtMostrar.WaitOne(0)) { Show-Main }
    # modo juego automático (aunque la ventana esté en la bandeja)
    if ($cfg.AutoJuego -and -not $Captura -and ((++$script:AutoTick) % 3) -eq 0) { Check-AutoJuego }
    # busca versión nueva al arrancar y después una vez por día (aunque quede días en la bandeja)
    if ($script:ProximoChequeo -and (Get-Date) -ge $script:ProximoChequeo) { Start-BuscarUpdate $false }
})
$timerOv.Start()

# la X (o Alt+F4) no cierra: manda a la bandeja
$win.Add_Closing({ if (-not $script:Saliendo) { $_.Cancel = $true; Hide-Main } })

$win.Add_ContentRendered({
    # abierto por la tarea programada (acceso directo o después de actualizar) Windows lo deja detrás de
    # las otras ventanas: un instante "siempre visible" lo trae al frente aunque no le den el foco
    if (-not $Captura) { $win.Topmost = $true; [void]$win.Activate(); $win.Topmost = $false }
    Update-Stats
    Add-Line 'Listo. Elegí una opción.' 'dim'
    if ($cfg.Overlay -or $Captura) { Set-Overlay $true }
    if ($Captura) {
        if ($SinDatos) { foreach ($k in $SinDatos -split ',') { Toggle-Dato $k.Trim() } }
        Start-Accion 'diagnostico'
        return
    }
    Show-Actualizado
    if ($EsAdminAhora) { Check-Instalacion }
    $script:ProximoChequeo = (Get-Date).AddSeconds(4)
})

function Texto-Instalar {
    "Se instala en Archivos de programa y deja un acceso directo con la paloma en el Escritorio. Desde ahí abre directo: sin el aviso de Windows y sin ventanas negras.`n`nSe puede desinstalar cuando quieras desde abajo a la derecha."
}

function Check-Instalacion {
    if (Test-Tarea) {
        # ya estaba instalado pero abrieron una versión más nueva del .bat: se actualiza solo, sin preguntar
        # (o lo instalaron desde el .bat y ahora abrieron el .exe: se pasa a usarlo)
        if ([version]$Version -gt (Get-VersionArchivo $InstBat) -or ($Exe -and -not (Test-Path -LiteralPath $InstExe))) {
            Install-Optimizador
            Add-Line "Instalación actualizada a la v$Version." 'ok'
        }
        $ui.UninstLink.Visibility = 'Visible'
        return
    }
    # sin instalar: el link queda siempre a mano, aunque hayan dicho "Ahora no" al cartel
    $ui.InstLink.Visibility = 'Visible'
    if ($cfg.NoInstalar) { return }
    Pedir-Instalar
}

function Pedir-Instalar {
    $ok = Show-Dialogo '¿Abrir siempre sin pedir permisos?' (Texto-Instalar) 'Instalar' 'Ahora no' 'escudo'
    if ($ok) {
        try {
            Install-Optimizador
            Add-Line 'Instalado: la próxima vez abrilo desde el acceso directo del Escritorio y no pide permisos.' 'ok'
            $ui.InstLink.Visibility = 'Collapsed'
            $ui.UninstLink.Visibility = 'Visible'
        } catch { Add-Line ("No se pudo instalar: " + $_.Exception.Message) 'err' }
    } else {
        $cfg.NoInstalar = $true; Save-Cfg   # el cartel no vuelve a salir solo; queda el link "Instalar"
    }
}

$ui.InstLink.Add_MouseLeftButtonUp({ Pedir-Instalar })

$ui.UninstLink.Add_MouseLeftButtonUp({
    $ok = Show-Dialogo '¿Desinstalar?' "Se borra la tarea, la copia en Archivos de programa y el acceso directo del Escritorio.`n`nVolvería a pedir permisos cada vez que lo abras." 'Desinstalar' 'Cancelar' 'alerta'
    if (-not $ok) { return }
    Uninstall-Optimizador
    $cfg.NoInstalar = $true; Save-Cfg
    $ui.UninstLink.Visibility = 'Collapsed'
    $ui.InstLink.Visibility = 'Visible'
    Add-Line 'Desinstalado. El programa sigue abierto hasta que lo cierres.' 'warn'
})

if ($Captura -and $Tema) { Set-Tema $Tema ([bool]$Claro) $true }
else { Set-Tema $cfg.Tema ([bool]$cfg.Claro) $true }
Apply-Admin
$ui.BtnOverlay.Foreground = $Colores.muted
$win.Show()
[void]$app.Run()

# ================================
# LOGO (paloma, JPEG en base64)
# ================================
#LOGO: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
