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
    [ValidateSet('', 'limpieza', 'juego', 'todo', 'diagnostico', 'reparar', 'red', 'restaurar', 'autojuego', 'finjuego', 'routerprobar')]
    [string]$Accion = '',
    [switch]$Simular,
    [string]$Captura = '',
    [string]$Tema = '',     # solo para capturas de prueba
    [string]$Estilo = '',   # idem: Solido, Vidrio, Neon
    [string]$Tamano = '',   # idem: Completo, Compacto
    [switch]$Claro,
    [string]$SinDatos = '', # solo para capturas de prueba: ej. 'ram,vram'
    [string]$Vista = '',    # solo para capturas de prueba: 'rendimiento' saca la pestaña Rendimiento
    [switch]$SinElevar,     # lo pasa Optimizador.exe: ya pidió permisos él (con su nombre y la paloma)
    [switch]$Bandeja,       # lo pasa la tarea de "Iniciar con Windows" (se llama así por la versión que abría en la bandeja)
    [switch]$Desinstalar    # desde Configuración > Aplicaciones > Desinstalar
)

$ErrorActionPreference = 'SilentlyContinue'
# los logs van a AppData para no ensuciar la carpeta del optimizador
$Raiz = Join-Path $env:LOCALAPPDATA 'Optimizador J.vps'
$Version = '3.63'
# el programa tal cual se abrió: si corre desde la copia instalada y la desinstalan, Instalar la reescribe desde acá
$Fuente = try { [IO.File]::ReadAllBytes($Archivo) } catch { $null }

# ================================
# UNA SOLA INSTANCIA
# ================================
# Si ya está abierto (por ejemplo en la bandeja), le avisa que se muestre y se cierra.

if (-not $Accion -and -not $Captura -and -not $Desinstalar) {
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
$ClaveDesinst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OptimizadorJvps'
# dónde está instalado: lo que eligieron en el instalador (queda en Aplicaciones instaladas) o Archivos de programa
$InstDirDefecto = Join-Path $env:ProgramFiles 'Optimizador J.vps'
$InstDir = try { [string](Get-ItemProperty -Path $ClaveDesinst -ErrorAction Stop).InstallLocation } catch { '' }
if (-not $InstDir) { $InstDir = $InstDirDefecto }
$InstBat = Join-Path $InstDir 'Optimizador.bat'
function Set-CarpetaInstalacion([string]$dir) {
    $script:InstDir = $dir
    $script:InstBat = Join-Path $dir 'Optimizador.bat'
    $script:InstExe = Join-Path $dir 'Optimizador.exe'
}
# Carpeta elegida en el instalador. Corre con permisos de administrador sin preguntar, así que tiene que quedar
# donde ningún programa sin permisos lo pueda cambiar: en Archivos de programa o en la raíz de un disco (D:\...).
# Adentro de otra carpeta (Juegos, Descargas) cualquiera podría renombrar la de arriba y poner otro programa en su lugar.
# Devuelve la ruta final ('...\Optimizador J.vps') o $null si no sirve.
function Resolve-CarpetaInstalacion([string]$elegida) {
    $elegida = $elegida.TrimEnd('\')
    $final = if ((Split-Path $elegida -Leaf) -eq 'Optimizador J.vps') { $elegida } else { Join-Path $elegida 'Optimizador J.vps' }
    $padre = (Split-Path $final).TrimEnd('\')
    $raiz = [IO.Path]::GetPathRoot($final).TrimEnd('\')
    $protegidas = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    if ($padre -eq $raiz -or $padre -in $protegidas) { $final } else { $null }
}
# carpeta fuera de Archivos de programa: se le dejan los mismos permisos que tiene esa (solo administradores modifican)
function Protect-Carpeta([string]$dir) {
    [void][JVps.Consola]::Correr('icacls.exe', "`"$dir`" /setowner *S-1-5-32-544")
    [void][JVps.Consola]::Correr('icacls.exe', "`"$dir`" /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX")
    # se revisa que haya quedado así: Usuarios, Usuarios autenticados y Todos sin permiso de escritura
    $abiertos = 'S-1-5-32-545', 'S-1-5-11', 'S-1-1-0'
    $malos = (Get-Acl -LiteralPath $dir).Access | Where-Object {
        $sid = try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { '' }
        $_.AccessControlType -eq 'Allow' -and $sid -in $abiertos -and ($_.FileSystemRights -band 0xD0046)   # escribir, agregar, borrar, cambiar permisos o dueño
    }
    if ($malos) { throw "no se pudo proteger la carpeta $dir." }
}

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

# la instalación por partes (el asistente las corre de a una para mostrar el avance)
function Install-Archivos {
    if (-not (Test-Path $InstDir)) { New-Item -ItemType Directory -Path $InstDir -ErrorAction Stop | Out-Null }
    $enProgramFiles = $InstDir.StartsWith($env:ProgramFiles, 'OrdinalIgnoreCase') -or (${env:ProgramFiles(x86)} -and $InstDir.StartsWith(${env:ProgramFiles(x86)}, 'OrdinalIgnoreCase'))
    if (-not $enProgramFiles) { Protect-Carpeta $InstDir }
    # abierto desde la copia instalada después de Desinstalar: el archivo ya no existe y no hay de dónde copiarlo
    # (antes quedaba la tarea sin programa y el acceso directo abría y cerraba)
    if ($Archivo -ne $InstBat -and (Test-Path -LiteralPath $Archivo)) { Copy-Item -LiteralPath $Archivo -Destination $InstBat -Force }
    elseif (-not (Test-Path -LiteralPath $InstBat) -and $Fuente) { [IO.File]::WriteAllBytes($InstBat, $Fuente) }
    if (-not (Test-Path -LiteralPath $InstBat)) { throw 'no se pudo copiar el programa a Archivos de programa.' }
    if ($Exe -and $Exe -ne $InstExe) { Copy-Item -LiteralPath $Exe -Destination $InstExe -Force }
    if ($logo) { Save-Ico $logo (Join-Path $InstDir 'paloma.ico') }
}
function Install-Tarea {
    # con el .exe instalado la tarea lo usa a él: así tampoco se asoma la consola de PowerShell
    $accion = if (Test-Path -LiteralPath $InstExe) { New-ScheduledTaskAction -Execute $InstExe -Argument '--directo' }
              else { New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Comando-Lanzar $InstBat) }
    $quien = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
    # sin límite de tiempo (si no, Windows la corta a las 72 h) y prioridad normal (por defecto las tareas van más lentas)
    $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Priority 4
    Register-ScheduledTask -TaskName $TareaNombre -Action $accion -Principal $quien -Settings $ajustes -Force -ErrorAction Stop | Out-Null
}
function Get-LnkEscritorio { Join-Path ([Environment]::GetFolderPath('Desktop')) 'Optimizador.lnk' }
function Get-LnkMenu { Join-Path ([Environment]::GetFolderPath('Programs')) 'Optimizador J.vps.lnk' }
function Set-AccesoDirecto([string]$lnk) {
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

# todo de una (al actualizar una instalación). Los accesos directos: los que se elijan; por defecto, los que ya había
function Install-Optimizador($escritorio = $null, $menu = $null) {
    if ($null -eq $escritorio) { $escritorio = (Test-Path -LiteralPath (Get-LnkEscritorio)) -or -not (Test-Tarea) }
    if ($null -eq $menu) { $menu = Test-Path -LiteralPath (Get-LnkMenu) }
    Install-Archivos
    Install-Tarea
    if ($escritorio) { Set-AccesoDirecto (Get-LnkEscritorio) }
    if ($menu) { Set-AccesoDirecto (Get-LnkMenu) }
    # si ya iniciaba con Windows, se rehace la tarea de inicio para que apunte a lo recién instalado
    if (Test-Inicio) { Set-Inicio $true }
    Register-Desinstalador
}

# entrada en Configuración > Aplicaciones instaladas: nombre, versión, ícono y botón Desinstalar
function Register-Desinstalador {
    $hayExe = Test-Path -LiteralPath $InstExe
    if (-not (Test-Path $ClaveDesinst)) { New-Item -Path $ClaveDesinst -Force | Out-Null }
    $kb = [int]((Get-ChildItem -LiteralPath $InstDir -File | Measure-Object Length -Sum).Sum / 1KB)
    $valores = [ordered]@{
        DisplayName     = 'Optimizador J.vps'
        DisplayVersion  = $Version
        Publisher       = 'J.vps'
        DisplayIcon     = $(if ($hayExe) { "$InstExe,0" } else { Join-Path $InstDir 'paloma.ico' })
        InstallLocation = $InstDir
        UninstallString = $(if ($hayExe) { "`"$InstExe`" --desinstalar" } else { 'powershell.exe ' + (Comando-Lanzar $InstBat '-Desinstalar') })
    }
    foreach ($k in $valores.Keys) { Set-ItemProperty -Path $ClaveDesinst -Name $k -Value $valores[$k] }
    foreach ($k in 'NoModify', 'NoRepair') { Set-ItemProperty -Path $ClaveDesinst -Name $k -Value 1 -Type DWord }
    Set-ItemProperty -Path $ClaveDesinst -Name EstimatedSize -Value $kb -Type DWord
}

# ---------- iniciar con Windows ----------
# Tarea aparte con disparador al iniciar sesión (la principal no tiene: es la que usa el acceso directo).
# Abre la ventana, con permisos y sin aviso, 20 s después de entrar (deja terminar de arrancar a Windows).
$TareaInicio = 'Optimizador J.vps (inicio)'
function Test-Inicio {
    # por COM y no con Get-ScheduledTask: ese tarda de medio segundo a 2 s y demoraba en abrir el menú de la bandeja
    try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); [void]$s.GetFolder('\').GetTask($TareaInicio); $true } catch { $false }
}
function Set-Inicio([bool]$prender) {
    if (-not $prender) { Unregister-ScheduledTask -TaskName $TareaInicio -Confirm:$false -ErrorAction SilentlyContinue; return }
    $usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $accion = if (Test-Path -LiteralPath $InstExe) { New-ScheduledTaskAction -Execute $InstExe -Argument '--directo --bandeja' }
              else { New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Comando-Lanzar $InstBat '-Bandeja') }
    $disparador = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    $disparador.Delay = 'PT20S'
    $quien = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Highest
    $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Priority 4
    Register-ScheduledTask -TaskName $TareaInicio -Action $accion -Trigger $disparador -Principal $quien -Settings $ajustes -Force -ErrorAction Stop | Out-Null
}

function Uninstall-Optimizador {
    Unregister-ScheduledTask -TaskName $TareaNombre -Confirm:$false
    Set-Inicio $false
    Remove-Item -Path $ClaveDesinst -Recurse -Force -ErrorAction SilentlyContinue
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Optimizador.lnk'
    if (Test-Path $lnk) {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        if ($s.Arguments -match [regex]::Escape($TareaNombre) -or $s.TargetPath -eq $InstExe) { Remove-Item $lnk -Force }
    }
    Remove-Item -LiteralPath (Get-LnkMenu) -Force -ErrorAction SilentlyContinue
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

# ---------- programas de consola sin ventana ----------
# Optimizador.exe no tiene consola: cada powercfg, netsh o nvidia-smi llamado con & abría una ventana negra
# que además le sacaba el foco al juego (Roblox se trababa con la pestaña Rendimiento abierta). Todo lo de
# consola pasa por acá: sin ventana y con la salida en el idioma de la consola (acentos bien).
if (-not ('JVps.Consola' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Globalization; using System.IO; using System.Text;
using System.Net; using System.Net.NetworkInformation; using System.Net.Sockets; using System.Security.Cryptography; using System.Text.RegularExpressions;
namespace JVps {
public static class Consola {
    static Process Nuevo(string exe, string args) {
        var oem = Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
        var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
            RedirectStandardError = true, RedirectStandardInput = true, StandardOutputEncoding = oem, StandardErrorEncoding = oem };
        var p = Process.Start(psi);
        p.StandardInput.Close();   // si algo pregunta (takeown), no se queda esperando
        return p;
    }
    // corre y devuelve lo que escribió (salida y errores); msMax -1 = sin límite
    public static string[] Correr(string exe, string args, int msMax) {
        try {
            using (var p = Nuevo(exe, args)) {
                var salida = p.StandardOutput.ReadToEndAsync(); var errores = p.StandardError.ReadToEndAsync();
                if (!p.WaitForExit(msMax < 0 ? int.MaxValue : msMax)) { try { p.Kill(); } catch { } }
                salida.Wait(3000); errores.Wait(3000);
                string t = (salida.IsCompleted ? salida.Result : "") + (errores.IsCompleted ? errores.Result : "");
                return t.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
            }
        } catch { return new string[0]; }
    }
    public static string[] Correr(string exe, string args) { return Correr(exe, args, 60000); }
    // para los largos (DISM, SFC): el proceso abierto, para leer el progreso renglón por renglón
    public static Process Abrir(string exe, string args) {
        var p = Nuevo(exe, args);
        p.StandardError.ReadToEndAsync();
        return p;
    }
}

// router Movistar Fibra (Askey / Mitrastar, firmware Broadcom): entrar con la contraseña de la etiqueta y reiniciarlo.
// El login es base64("admin:" + md5(sid + ":" + clave)), igual que la página; el reinicio es rebootinfo.cgi con
// la clave de sesión que trae resetrouter.html. Registro junta lo que pasó (sin contraseñas) por si un modelo no anda.
public class Router {
    public readonly string Ip;
    public readonly List<string> Registro = new List<string>();
    readonly CookieContainer galletas = new CookieContainer();
    public Router(string ip) { Ip = ip; }
    class Resp { public int Codigo; public string Texto = ""; public string Destino = ""; }

    Resp Pedir(string ruta, string post, int ms) {
        var r = new Resp();
        var req = (HttpWebRequest)WebRequest.Create("http://" + Ip + ruta);
        req.CookieContainer = galletas; req.AllowAutoRedirect = false; req.Proxy = null;
        req.Timeout = ms; req.ReadWriteTimeout = ms;
        req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"; req.Referer = "http://" + Ip + "/";
        if (post != null) {
            req.Method = "POST"; req.ContentType = "application/x-www-form-urlencoded";
            var b = Encoding.ASCII.GetBytes(post); req.ContentLength = b.Length;
            using (var st = req.GetRequestStream()) st.Write(b, 0, b.Length);
        }
        HttpWebResponse resp;
        try { resp = (HttpWebResponse)req.GetResponse(); }
        catch (WebException e) { resp = e.Response as HttpWebResponse; if (resp == null) throw; }
        using (resp) {
            r.Codigo = (int)resp.StatusCode;
            r.Destino = resp.Headers["Location"] ?? "";
            using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) r.Texto = sr.ReadToEnd();
        }
        if (r.Destino == "" && r.Texto.Length < 600) {   // redirige con javascript: top.location='...'
            var m = Regex.Match(r.Texto, @"(?:top|window)\.location(?:\.href)?\s*=\s*['""]([^'""]+)['""]");
            if (m.Success) r.Destino = m.Groups[1].Value;
        }
        return r;
    }
    static bool EsLogin(Resp r) {
        return r.Codigo == 401 || r.Texto.Contains("passWarning") || r.Destino.IndexOf("logIn", StringComparison.OrdinalIgnoreCase) >= 0;
    }
    static string Md5(string s) {
        var sb = new StringBuilder();
        using (var md5 = MD5.Create()) foreach (var b in md5.ComputeHash(Encoding.GetEncoding(28591).GetBytes(s))) sb.Append(b.ToString("x2"));
        return sb.ToString();
    }
    void Log(string t) { Registro.Add(Regex.Replace(t, @"(sessionKey\s*[=:]\s*'?)\w+", m => m.Groups[1].Value + "...")); }

    // la página de inicio del router es la del Movistar Fibra
    public static bool Compatible(string html) {
        return html != null && html.Contains("login-login.cgi") && Regex.IsMatch(html, @"var\s+sid\s*=");
    }

    // null = entró; si no, el motivo
    public string Entrar(string clave) {
        var ini = Pedir("/", null, 8000);
        var sid = Regex.Match(ini.Texto, @"var\s+sid\s*=\s*""([^""]+)""");
        if (!sid.Success) { Log("sin página de login (código " + ini.Codigo + ")"); return "La página del router no es la de un Movistar Fibra"; }
        string usuario = Regex.IsMatch(ini.Texto, @"var\s+supportArgentina\s*=\s*'1'") ? "admin" : "Support";
        string k = Convert.ToBase64String(Encoding.GetEncoding(28591).GetBytes(usuario + ":" + Md5(sid.Groups[1].Value + ":" + clave)));
        var r = Pedir("/login-login.cgi", "sessionKey=" + Uri.EscapeDataString(k) + "&pass=", 10000);
        Log("login: código " + r.Codigo + ", destino " + r.Destino);
        return EsLogin(r) ? "Contraseña incorrecta" : null;
    }

    // la dirección para reiniciar este modelo, o null si no la encuentra
    public string BuscarReinicio() {
        foreach (var pagina in new[] { "/resetrouter.html", "/resetrouter.htm", "/reboot.html" }) {
            Resp p;
            try { p = Pedir(pagina, null, 8000); } catch (Exception e) { Log(pagina + ": " + e.Message); continue; }
            Log(pagina + ": código " + p.Codigo + ", " + p.Texto.Length + " bytes");
            if (p.Codigo != 200 || EsLogin(p)) continue;
            var clave = Regex.Match(p.Texto, @"sessionKey\s*[=:]\s*['""]?(\w+)");
            var accion = Regex.Match(p.Texto, @"(\w*reboot\w*\.(?:cgi|cmd))", RegexOptions.IgnoreCase);
            return "/" + (accion.Success ? accion.Groups[1].Value : "rebootinfo.cgi") + (clave.Success ? "?sessionKey=" + clave.Groups[1].Value : "");
        }
        return null;
    }

    // true si aceptó la orden (o cortó porque ya se está apagando)
    public bool Reiniciar(string ruta) {
        try {
            var r = Pedir(ruta, null, 8000);
            Log("reinicio: código " + r.Codigo);
            return r.Codigo == 200 && !EsLogin(r);
        } catch (WebException e) { Log("reinicio: se cortó (" + e.Status + ")"); return true; }
    }

    // puerta de enlace de la conexión activa
    public static string Puerta() {
        try {
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) {
                if (n.OperationalStatus != OperationalStatus.Up || n.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var g in n.GetIPProperties().GatewayAddresses)
                    if (g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)) return g.Address.ToString();
            }
        } catch { }
        return null;
    }
}
}
"@
}
# ---------- programas que arrancan con Windows ----------
# Los mismos que muestra el Administrador de tareas:
#  - Run del registro y carpetas de Inicio: prendido/apagado va en StartupApproved (primer byte par = activo, impar = apagado)
#  - apps de la Tienda (Teams, Spotify, WhatsApp...): cada una tiene su tarea de inicio con State (2/4 = activa)
# Apagar no borra nada: el programa sigue instalado y se vuelve a prender con el mismo switch (o desde el
# Administrador de tareas). Lo usan la pestaña Arranque y la Revisión completa (va pegado adelante de $Core).
$FnInicio = {
    function Get-ExeDeComando([string]$cmd) {
        $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
        if ($c -match '^"([^"]+)"') { return $Matches[1] }
        if ($c -match '^(.+?\.(exe|com|bat|cmd))(\s|$)') { return $Matches[1] }
        ($c -split '\s+')[0]
    }

    # consejo: 'apagar' = no hace falta al prender, 'dejar' = sistema/sonido/antivirus
    function Get-ConsejoInicio([string]$txt, [bool]$existe) {
        if (-not $existe) { return 'apagar', 'El programa ya no está: se puede apagar sin problema' }
        if ($txt -match 'SecurityHealth|Defender|Malwarebytes|Avast|\bAVG\b|Kaspersky|ESET|Bitdefender|Norton|McAfee|Avira|Realtek|Synaptics|\bELAN\b|SmartAudio|MaxxAudio|Waves|Dolby|IAStor|igfx|RadeonSoftware|AMD Software') { return 'dejar', 'Sistema, sonido o antivirus: mejor dejarlo' }
        if ($txt -match 'Steam|EpicGames|Battle\.net|EADesktop|\bOrigin\b|Ubisoft|upc\.exe|GalaxyClient|Riot ?Client|Rockstar|Spotify|Teams|Skype|Zoom|Opera|MicrosoftEdgeAutoLaunch|CCleaner|Adobe|Creative ?Cloud|uTorrent|BitTorrent|qBittorrent|iTunesHelper|Cortana|Telegram|WhatsApp|Overwolf|Medal|Outplayed|Lightshot|Docker|Postman|Google ?Drive|Dropbox|MEGAsync|Messenger|BlueStacks|Roblox|Gaijin|Autodesk|Java Update|Copilot|ChatGPT|Microsoft 365|\bXBOX\b|GamingApp|Samsung Notes|YourPhone|Enlace M|Phone Link|CrossDevice|Dispositivos m|StartExperiences|Experiencias de inicio') { return 'apagar', 'Se puede abrir cuando lo uses' }
        if ($txt -match 'Discord') { return '', 'Si lo usás siempre al prender la PC, dejalo' }
        if ($txt -match 'OneDrive') { return '', 'Sincroniza tus archivos con la nube: si no lo usás, apagalo' }
        if ($txt -match 'Logitech|LGHUB|Razer|Corsair|iCUE|SteelSeries|HyperX|NGenuity|Armoury|\bAura\b|Redragon|Wooting|FURY ?CTRL') { return '', 'Luces o periféricos: apagado, pueden quedar sin su configuración hasta que lo abras' }
        return '', ''
    }

    function New-ItemInicio($valor, $exe, $colmena, $sub) {
        $raiz = if ($colmena -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
        $b = $null
        $ka = $raiz.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub")
        if ($ka) { $b = $ka.GetValue($valor); $ka.Close() }
        $activo = -not ($b -is [byte[]] -and $b.Length -and ($b[0] -band 1))

        $existe = $exe -and (Test-Path -LiteralPath $exe -PathType Leaf)
        if (-not $existe -and $exe -and -not [IO.Path]::IsPathRooted($exe)) {
            $w = (Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
            if ($w) { $exe = $w; $existe = $true }
        }
        $vi = if ($existe) { try { [Diagnostics.FileVersionInfo]::GetVersionInfo($exe) } catch { $null } }
        # solo los de la carpeta son archivos: "electron.app.YouTube Music" no tiene extensión que sacar
        $base = $(if ($sub -eq 'StartupFolder') { [IO.Path]::GetFileNameWithoutExtension($valor) } else { $valor }) -replace '^(electron\.app|com\.squirrel)\.', ''
        # rundll32, Update.exe de Discord, etc. son lanzadores o tienen una descripción genérica ("Update",
        # "Starter Module"): ahí el nombre del valor dice mejor qué programa es
        $desc = if ($vi) { ([string]$vi.FileDescription).Trim() } else { '' }
        $generico = $exe -match '\\(rundll32|cmd|powershell|pwsh|wscript|cscript|conhost|explorer|mshta|update)\.exe$' -or
            $desc -match '^(Update|Updater|Launcher|Setup|Helper|Starter Module|Module|Service|Agent|Bootstrapper|electron\.app)$'
        $nombre = if ($desc -and -not $generico) { $desc } else { $base }
        $editor = if ($vi) { ([string]$vi.CompanyName).Trim() } else { '' }
        $tipo, $nota = Get-ConsejoInicio "$valor $exe $nombre $editor" $existe

        [PSCustomObject]@{ Nombre = $nombre; Editor = $editor; Exe = $(if ($existe) { $exe }); Logo = $null; Valor = $valor
            Colmena = $colmena; Sub = $sub; Clave = $null; Activo = $activo; Tipo = $tipo; Nota = $nota; Politica = $false }
    }

    # apps de la Tienda: HKCU\...\AppModel\SystemAppData\<familia>\<tarea>\State
    # 0 = apagada, 1 = apagada por el usuario, 2 = prendida, 3/4 = la maneja una política (no se puede cambiar)
    # -Detalles lee además el editor y el logo del manifiesto (tarda ~1 s: la Revisión no lo necesita)
    function Get-AppsTiendaInicio([switch]$Detalles) {
        if (-not ('IndStr' -as [type])) { Add-Type -Name IndStr -Namespace '' -MemberDefinition '[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)] public static extern int SHLoadIndirectString(string s, System.Text.StringBuilder o, int n, IntPtr r);' }
        # registro por .NET directo: Get-ChildItem sobre ~150 claves tarda casi un segundo
        $am = 'Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel'
        $hk = [Microsoft.Win32.Registry]::CurrentUser
        $rp = $hk.OpenSubKey("$am\Repository\Packages"); $sa = $hk.OpenSubKey("$am\SystemAppData")
        if (-not $rp -or -not $sa) { return }
        # paquete instalado por familia (Nombre_Version_Arq__Editor → Nombre_Editor), sin los de recursos; la versión más nueva
        $paquetes = @{}
        foreach ($pn in ($rp.GetSubKeyNames() | Sort-Object)) {
            if ($pn -match '_split\.|_~_' -or $pn -notmatch '^([^_]+)_.*__([^_]+)$') { continue }
            $paquetes["$($Matches[1])_$($Matches[2])"] = $pn
        }
        foreach ($f in $sa.GetSubKeyNames()) {
            $pkn = $paquetes[$f]
            if (-not $pkn) { continue }   # no es una app con tarea de inicio, o quedó de una desinstalada
            $n = $f -replace '_[^_]+$', ''
            $kf = $sa.OpenSubKey($f)
            foreach ($tn in $kf.GetSubKeyNames()) {
                $kt = $kf.OpenSubKey($tn); $st = $kt.GetValue('State'); $kt.Close()
                if ($null -eq $st) { continue }
                $kp = $rp.OpenSubKey($pkn)
                $pp = @{ DisplayName = $kp.GetValue('DisplayName'); PackageRootFolder = $kp.GetValue('PackageRootFolder') }; $kp.Close()
                $pk = @{ PSChildName = $pkn }
                $t = @{ PSChildName = $tn; PSPath = "Registry::HKEY_CURRENT_USER\$am\SystemAppData\$f\$tn" }
                $nombre = [string]$pp.DisplayName
                if ($nombre -like 'ms-resource:*') {
                    $r = $nombre.Substring(12)
                    $uri = if ($r.StartsWith('//')) { "ms-resource:$r" } elseif ($r -match '/') { "ms-resource://$n/" + $r.TrimStart('/') } else { "ms-resource://$n/Resources/$r" }
                    $sb = New-Object Text.StringBuilder 512
                    $nombre = if ([IndStr]::SHLoadIndirectString("@{$($pk.PSChildName)?$uri}", $sb, 512, [IntPtr]::Zero) -eq 0 -and $sb.Length) { "$sb" } else { $n -replace '^.*\.', '' }
                }
                $editor = ''; $logo = $null
                if ($Detalles) {
                    try {
                        $m = [xml](Get-Content -LiteralPath (Join-Path $pp.PackageRootFolder 'AppxManifest.xml') -Raw -ErrorAction Stop)
                        $editor = [string]$m.Package.Properties.PublisherDisplayName
                        # el logo tiene variantes por escala (StoreLogo.scale-100.png...): la más grande
                        $l = [string]$m.Package.Properties.Logo
                        $logo = (Get-ChildItem -LiteralPath (Join-Path $pp.PackageRootFolder (Split-Path $l)) -Filter ([IO.Path]::GetFileNameWithoutExtension($l) + '*.png') -ErrorAction Stop | Sort-Object Length -Descending | Select-Object -First 1).FullName
                    } catch { }
                }
                $tipo, $nota = Get-ConsejoInicio "$f $nombre $editor" $true
                if ([int]$st -ge 3) { $nota = 'Lo maneja tu empresa o escuela: no se puede cambiar' }
                [PSCustomObject]@{ Nombre = $nombre; Editor = $editor; Exe = $null; Logo = $logo; Valor = $t.PSChildName
                    Colmena = 'Tienda'; Sub = $null; Clave = $t.PSPath; Activo = ([int]$st -in 2, 4); Tipo = $tipo; Nota = $nota; Politica = ([int]$st -ge 3) }
            }
            $kf.Close()
        }
        $rp.Close(); $sa.Close()
    }

    function Get-ProgramasInicio([switch]$Detalles) {
        $lista = New-Object Collections.ArrayList
        foreach ($f in @(@('HKCU', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'Run'),
                         @('HKLM', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'Run'),
                         @('HKLM', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'Run32'))) {
            $k = Get-Item -LiteralPath $f[1] -ErrorAction SilentlyContinue
            if (-not $k) { continue }
            foreach ($n in $k.GetValueNames()) {
                $cmd = [string]$k.GetValue($n)
                if (-not $n -or -not $cmd.Trim()) { continue }
                [void]$lista.Add((New-ItemInicio $n (Get-ExeDeComando $cmd) $f[0] $f[2]))
            }
        }
        $sh = New-Object -ComObject WScript.Shell
        foreach ($f in @(@('HKCU', [Environment]::GetFolderPath('Startup')), @('HKLM', [Environment]::GetFolderPath('CommonStartup')))) {
            if (-not $f[1] -or -not (Test-Path -LiteralPath $f[1])) { continue }
            foreach ($a in @(Get-ChildItem -LiteralPath $f[1] -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                $exe = $a.FullName
                if ($a.Extension -eq '.lnk') { try { $t = $sh.CreateShortcut($a.FullName).TargetPath; if ($t) { $exe = $t } } catch { } }
                [void]$lista.Add((New-ItemInicio $a.Name $exe $f[0] 'StartupFolder'))
            }
        }
        foreach ($x in @(Get-AppsTiendaInicio -Detalles:$Detalles)) { [void]$lista.Add($x) }
        $lista
    }

    # HKLM necesita permisos de administrador: si no, tira error (lo ataja quien llama)
    function Set-ProgramaInicio($p, [bool]$activo) {
        if ($p.Colmena -eq 'Tienda') {
            if ($p.Politica) { throw 'lo maneja una política de tu empresa o escuela' }
            Set-ItemProperty -LiteralPath $p.Clave -Name State -Value $(if ($activo) { 2 } else { 1 }) -Type DWord -ErrorAction Stop
            $p.Activo = $activo; return
        }
        $raiz = if ($p.Colmena -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
        $k = $raiz.CreateSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$($p.Sub)")
        $b = New-Object byte[] 12
        $b[0] = if ($activo) { 2 } else { 3 }
        if (-not $activo) { [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) }   # cuándo se apagó (lo muestra el Administrador de tareas)
        $k.SetValue($p.Valor, $b, [Microsoft.Win32.RegistryValueKind]::Binary); $k.Close()
        $p.Activo = $activo
    }
}
. $FnInicio

# ---------- Espacio: qué ocupa el disco y qué se puede liberar ----------
# Recorre carpetas con FindFirstFileEx (mucho más rápido que Get-ChildItem -Recurse): mide el disco entero para la
# pestaña Carpetas, mide cada categoría de Limpiar y borra lo de adentro salteando lo que está en uso.
# Los enlaces (junctions) no se siguen: si no, carpetas como "Datos de programa" se contarían dos veces.
$EscanerCs = @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace JVps {
public class Escaner {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WFD {
        public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME C, A, W; public uint Hi, Lo, R0, R1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Nombre;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string Alt;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindFirstFileExW(string f, int nivel, out WFD d, int op, IntPtr filtro, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool FindNextFileW(IntPtr h, out WFD d);
    [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool DeleteFileW(string f);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool RemoveDirectoryW(string d);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetFileAttributesW(string f, uint a);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetCompressedFileSizeW(string f, out uint alto);
    static readonly IntPtr Invalido = new IntPtr(-1);
    const uint Carpeta = 0x10, Enlace = 0x400, SoloLectura = 0x1;
    const uint Disperso = 0x200, Comprimido = 0x800, Offline = 0x1000, EnLaNube = 0x400000;

    // lo que ocupa de verdad en el disco: un disperso (discos virtuales de emuladores, Docker, WSL) dice 512 GB
    // y ocupa lo que usa; uno de la nube sin bajar (OneDrive) no ocupa nada
    static long Real(string p, WFD d) {
        if ((d.Attr & (Offline | EnLaNube)) != 0) return 0;
        long s = ((long)d.Hi << 32) | d.Lo;
        if ((d.Attr & (Disperso | Comprimido)) != 0) {
            uint alto; uint bajo = GetCompressedFileSizeW(@"\\?\" + p, out alto);
            if (bajo != 0xFFFFFFFF || Marshal.GetLastWin32Error() == 0) s = ((long)alto << 32) | bajo;
        }
        return s;
    }

    // progreso (lo lee la ventana mientras analiza)
    public long Bytes, Archivos, SinPermiso;
    public string Actual = "";
    public volatile bool Cancelar, Termino;
    // resultado: tamaño de cada carpeta hasta Profundidad niveles, sus hijas y los archivos más grandes
    public int Profundidad = 7;
    public Dictionary<string, long> Carpetas = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, List<string>> Hijos = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
    public List<KeyValuePair<string, long>> Grandes = new List<KeyValuePair<string, long>>();
    const int MaxGrandes = 80;
    long minimo;

    public void Escanear(string raiz) {
        raiz = raiz.TrimEnd('\\');
        try { Medir(raiz, 0); }
        finally {
            foreach (var k in Carpetas.Keys) {
                int i = k.LastIndexOf('\\'); if (i < 0) continue;
                string p = k.Substring(0, i); List<string> l;
                if (!Hijos.TryGetValue(p, out l)) Hijos[p] = l = new List<string>();
                l.Add(k);
            }
            Grandes.Sort((x, y) => y.Value.CompareTo(x.Value));
            Termino = true;
        }
    }

    long Medir(string dir, int prof) {
        if (Cancelar) return 0;
        if (prof <= 4) Actual = dir;
        long total = 0; WFD d;
        IntPtr h = FindFirstFileExW(@"\\?\" + dir + @"\*", 1, out d, 0, IntPtr.Zero, 2);   // 1 = sin nombre corto, 2 = de a muchos
        if (h == Invalido) { SinPermiso++; return 0; }
        try {
            do {
                if (d.Nombre == "." || d.Nombre == "..") continue;
                string p = dir + "\\" + d.Nombre;
                if ((d.Attr & Carpeta) != 0) { if ((d.Attr & Enlace) == 0) total += Medir(p, prof + 1); }
                else { long s = Real(p, d); total += s; Bytes += s; Archivos++; if (Profundidad >= 0) Anotar(p, s); }
            } while (!Cancelar && FindNextFileW(h, out d));
        } finally { FindClose(h); }
        if (prof <= Profundidad) Carpetas[dir] = total;
        return total;
    }

    void Anotar(string p, long s) {
        if (Grandes.Count >= MaxGrandes && s <= minimo) return;
        Grandes.Add(new KeyValuePair<string, long>(p, s));
        if (Grandes.Count > MaxGrandes) {
            int im = 0;
            for (int i = 1; i < Grandes.Count; i++) if (Grandes[i].Value < Grandes[im].Value) im = i;
            Grandes.RemoveAt(im);
        }
        if (Grandes.Count >= MaxGrandes) { minimo = long.MaxValue; foreach (var g in Grandes) if (g.Value < minimo) minimo = g.Value; }
    }

    // tamaño de una carpeta (categorías de Limpiar)
    public static long Tam(string dir) { var e = new Escaner(); e.Profundidad = -1; return e.Medir(dir.TrimEnd('\\'), 0); }

    // borra todo lo de adentro (la carpeta queda); lo que está en uso se saltea. Devuelve los bytes borrados
    public static long Vaciar(string dir) { return Borrar(dir.TrimEnd('\\'), false); }
    static long Borrar(string dir, bool tambienCarpeta) {
        long lib = 0; WFD d;
        IntPtr h = FindFirstFileExW(@"\\?\" + dir + @"\*", 1, out d, 0, IntPtr.Zero, 2);
        if (h != Invalido) {
            try {
                do {
                    if (d.Nombre == "." || d.Nombre == "..") continue;
                    string p = @"\\?\" + dir + "\\" + d.Nombre;
                    if ((d.Attr & Carpeta) != 0) {
                        if ((d.Attr & Enlace) != 0) RemoveDirectoryW(p);   // enlace: se saca el enlace, no lo que apunta
                        else lib += Borrar(dir + "\\" + d.Nombre, true);
                    } else {
                        long s = Real(dir + "\\" + d.Nombre, d);
                        if ((d.Attr & SoloLectura) != 0) SetFileAttributesW(p, 0x80);
                        if (DeleteFileW(p)) lib += s;
                    }
                } while (FindNextFileW(h, out d));
            } finally { FindClose(h); }
        }
        if (tambienCarpeta) RemoveDirectoryW(@"\\?\" + dir);   // si quedó algo en uso no está vacía y no se borra
        return lib;
    }
}
}
'@

$FnEspacio = {
    function Format-Tam([double]$b) {
        if ($b -ge 1000MB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } elseif ($b -ge 1KB) { '{0:N0} KB' -f ($b / 1KB) } else { '0 MB' }
    }

    function Use-Escaner { if (-not ('JVps.Escaner' -as [type])) { Add-Type -TypeDefinition $EscanerCs } }

    # Papelera del usuario en cada disco: $Recycle.Bin\<SID> (la de otros usuarios no se puede leer)
    function Get-RutasPapelera {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "$($_.DeviceID)\`$Recycle.Bin\$sid" } | Where-Object { Test-Path -LiteralPath $_ })
    }

    function Measure-Categoria($c) {
        $tam = [long]0; $existe = $false
        foreach ($r in @($c.Rutas)) { if ($r -and (Test-Path -LiteralPath $r -ErrorAction SilentlyContinue)) { $existe = $true; $tam += [JVps.Escaner]::Tam($r) } }
        foreach ($a in @($c.Archivos)) { if ($a) { foreach ($f in @(Get-ChildItem -Path $a -Force -File -ErrorAction SilentlyContinue)) { $existe = $true; $tam += $f.Length } } }
        @{ Tam = $tam; Existe = $existe }
    }

    # cada categoría: Grupo 'seguro' (se rehace sola, va marcada) o 'revisar' (tiene una contra, va sin marcar)
    function Get-CategoriasEspacio {
        Use-Escaner
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $L = $env:LOCALAPPDATA; $R = $env:APPDATA; $W = $env:WINDIR; $PD = $env:ProgramData; $SD = $env:SystemDrive
        $nav = foreach ($b in 'Google\Chrome', 'Microsoft\Edge', 'BraveSoftware\Brave-Browser', 'Vivaldi', 'Chromium') { foreach ($k in 'Cache', 'Code Cache', 'GPUCache') { "$L\$b\User Data\*\$k" } }
        $nav = @($nav) + "$L\Opera Software\*\Cache", "$L\Opera Software\*\Code Cache", "$R\Opera Software\*\GPUCache", "$L\Mozilla\Firefox\Profiles\*\cache2"
        $nav = @(foreach ($p in $nav) { Resolve-Path -Path $p -ErrorAction SilentlyContinue | ForEach-Object ProviderPath })
        $dc = foreach ($v in 'discord', 'discordcanary', 'discordptb') { foreach ($k in 'Cache', 'Code Cache', 'GPUCache') { "$R\$v\$k" } }
        $fivem = "$L\FiveM\FiveM.app\data"
        $fivemAbierto = [bool](Get-Process -Name 'FiveM*' -ErrorAction SilentlyContinue)

        $defs = @(
            @{ Id = 'temp'; Grupo = 'seguro'; Nombre = 'Archivos temporales'; Desc = 'Lo que dejan los programas y los instaladores al terminar'; Rutas = $env:TEMP, "$W\Temp" }
            @{ Id = 'wu'; Grupo = 'seguro'; Admin = $true; Nombre = 'Actualizaciones de Windows ya instaladas'; Desc = 'Los instaladores que Windows Update bajó y ya usó'; Rutas = "$W\SoftwareDistribution\Download" }
            @{ Id = 'do'; Grupo = 'seguro'; Admin = $true; Nombre = 'Optimización de distribución'; Desc = 'Actualizaciones guardadas para pasarle a otras PCs'; Rutas = "$W\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Especial = 'do' }
            @{ Id = 'wer'; Grupo = 'seguro'; Nombre = 'Reportes de errores'; Desc = 'Informes de programas que se colgaron'; Rutas = "$PD\Microsoft\Windows\WER\ReportArchive", "$PD\Microsoft\Windows\WER\ReportQueue", "$L\CrashDumps", "$W\LiveKernelReports" }
            @{ Id = 'thumb'; Grupo = 'seguro'; Nombre = 'Caché de miniaturas'; Desc = 'Las vistas previas de fotos y videos: se rehacen solas'; Archivos = "$L\Microsoft\Windows\Explorer\thumbcache_*.db" }
            @{ Id = 'nav'; Grupo = 'seguro'; Nombre = 'Caché de los navegadores'; Desc = 'Chrome, Edge, Opera, Brave y Firefox. No toca contraseñas, historial ni sesiones'; Rutas = $nav }
            @{ Id = 'discord'; Grupo = 'seguro'; Nombre = 'Caché de Discord'; Desc = 'Imágenes y videos que ya viste en los chats'; Rutas = $dc }
            @{ Id = 'drv'; Grupo = 'seguro'; Nombre = 'Instaladores viejos de drivers'; Desc = 'Lo que quedó de instalar drivers de NVIDIA y AMD'; Rutas = "$PD\NVIDIA Corporation\Downloader", "$SD\NVIDIA", "$SD\AMD" }
            @{ Id = 'papelera'; Grupo = 'revisar'; Nombre = 'Papelera de reciclaje'; Desc = 'Lo que borraste: después ya no se puede recuperar'; Rutas = Get-RutasPapelera; Especial = 'papelera' }
            @{ Id = 'fivem'; Grupo = 'revisar'; Nombre = 'Caché de servers de FiveM'; Desc = 'Se vuelve a bajar al entrar a cada server (la primera vez tarda más en cargar)'; Rutas = "$fivem\server-cache-priv", "$fivem\server-cache", "$fivem\cache"; Bloqueo = $(if ($fivemAbierto) { 'Cerrá FiveM para poder borrarla' }) }
            @{ Id = 'shader'; Grupo = 'revisar'; Nombre = 'Caché de shaders de la placa de video'; Desc = 'Se rehace sola, pero cada juego tarda un poco más la primera vez que lo abrís'; Rutas = "$L\NVIDIA\DXCache", "$L\NVIDIA\GLCache", "$L\D3DSCache", "$L\AMD\DxCache", "$L\AMD\DxcCache", "$L\AMD\GLCache" }
            @{ Id = 'dump'; Grupo = 'revisar'; Admin = $true; Nombre = 'Volcado del último pantallazo azul'; Desc = 'Sirve para investigar el pantallazo. Si ya no te pasan, se puede borrar'; Archivos = "$W\MEMORY.DMP" }
            @{ Id = 'hiber'; Grupo = 'revisar'; Admin = $true; Nombre = 'Archivo de hibernación'; Desc = 'Apaga la hibernación y el Inicio rápido. En una PC de escritorio casi no se usan'; Archivos = "$SD\hiberfil.sys"; Especial = 'hiber' }
            @{ Id = 'winold'; Grupo = 'revisar'; Admin = $true; Nombre = 'Windows anterior (Windows.old)'; Desc = 'Después ya no vas a poder volver a la versión de Windows que tenías antes'; Rutas = "$SD\Windows.old"; Especial = 'winold' }
        )
        foreach ($d in $defs) {
            $m = Measure-Categoria $d
            # lo que no existe en esta PC (FiveM, Discord, Windows.old, hibernación apagada...) no se muestra. Salvo lo que
            # necesita administrador y no lo es: sin permisos a veces ni se puede ver si existe, y ahí avisa
            if (-not $m.Existe -and -not ($d.Admin -and -not $admin)) { continue }
            [PSCustomObject]@{ Id = $d.Id; Grupo = $d.Grupo; Nombre = $d.Nombre; Desc = $d.Desc; Rutas = @($d.Rutas); Archivos = @($d.Archivos); Especial = $d.Especial
                Tam = $m.Tam; Libre = $m.Tam; Resto = [long]0; Motivo = $(if ($d.Admin -and -not $admin) { 'Hace falta abrir el Optimizador con permisos de administrador' } elseif ($d.Bloqueo) { $d.Bloqueo } else { '' }) }
        }
    }

    # borra lo elegido; lo liberado se mide antes y después (lo que está en uso queda y no cuenta)
    function Invoke-LimpiarEspacio($cats) {
        Use-Escaner
        $res = @(); $i = 0
        foreach ($c in $cats) {
            $i++
            $sync.Q.Enqueue(@{ Tipo = 'esplimp'; I = $i; N = @($cats).Count; L = $c.Nombre })
            try {
                switch ($c.Especial) {
                    'papelera' { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
                    'hiber' { [void][JVps.Consola]::Correr('powercfg', '/hibernate off'); Start-Sleep -Milliseconds 800 }
                    'do' { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { foreach ($r in $c.Rutas) { [void][JVps.Escaner]::Vaciar($r) } } }
                    'winold' {
                        # Windows.old es de TrustedInstaller: primero se toma posesión y se dan permisos a Administradores
                        $r = $c.Rutas[0]
                        $si = if ([Globalization.CultureInfo]::InstalledUICulture.TwoLetterISOLanguageName -eq 'es') { 'S' } else { 'Y' }
                        [void][JVps.Consola]::Correr('takeown', "/F `"$r`" /R /A /D $si", -1)
                        [void][JVps.Consola]::Correr('icacls', "`"$r`" /grant *S-1-5-32-544:F /T /C /Q", -1)
                        [void][JVps.Escaner]::Vaciar($r)
                        Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    default {
                        foreach ($r in $c.Rutas) { if ($r -and (Test-Path -LiteralPath $r)) { [void][JVps.Escaner]::Vaciar($r) } }
                        foreach ($a in $c.Archivos) { if ($a) { Get-ChildItem -Path $a -Force -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue } }
                    }
                }
            } catch { }
            $despues = (Measure-Categoria $c).Tam
            $res += @{ Id = $c.Id; Nombre = $c.Nombre; Lib = [math]::Max([long]0, [long]$c.Tam - $despues); Resto = $despues }
        }
        # registro del día, como las demás acciones
        try {
            $dir = Join-Path $Raiz 'logs'
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
            $txt = 'Liberar espacio: ' + (($res | ForEach-Object { "$($_.Nombre) $(Format-Tam $_.Lib)" }) -join ', ')
            Add-Content -Path (Join-Path $dir ('optimizador_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Value ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $txt) -Encoding UTF8
        } catch { }
        $res
    }

    # juegos de Steam (todas las bibliotecas) y Epic, con su tamaño y cuándo se jugó por última vez (solo Steam lo guarda)
    function Get-JuegosInstalados {
        $j = New-Object Collections.ArrayList
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steam) {
            $steam = $steam -replace '/', '\'
            $libs = @($steam)
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw -Encoding UTF8), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
            }
            foreach ($lib in ($libs | Sort-Object -Unique)) {
                foreach ($a in @(Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
                    $t = Get-Content -LiteralPath $a.FullName -Raw -Encoding UTF8
                    $v = @{}
                    foreach ($m in [regex]::Matches($t, '"(appid|name|SizeOnDisk|LastPlayed|installdir)"\s+"([^"]*)"')) { if (-not $v.ContainsKey($m.Groups[1].Value)) { $v[$m.Groups[1].Value] = $m.Groups[2].Value } }
                    if (-not $v.name -or $v.name -match 'Steamworks|Redistributable|Proton|Steam Linux Runtime') { continue }
                    $jug = if ([long]$v.LastPlayed -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds([long]$v.LastPlayed).LocalDateTime }
                    [void]$j.Add([PSCustomObject]@{ Nombre = ($v.name -replace '[®™]', '').Trim(); Tienda = 'Steam'; Id = $v.appid; Ruta = (Join-Path $lib "steamapps\common\$($v.installdir)"); Tam = [long]$v.SizeOnDisk; Jugado = $jug })
                }
            }
        }
        foreach ($f in @(Get-ChildItem -LiteralPath "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter *.item -ErrorAction SilentlyContinue)) {
            try { $x = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            if (-not $x.DisplayName -or $x.bIsIncompleteInstall -or -not (Test-Path -LiteralPath $x.InstallLocation)) { continue }
            [void]$j.Add([PSCustomObject]@{ Nombre = ($x.DisplayName -replace '[®™]', '').Trim(); Tienda = 'Epic'; Id = $x.AppName; Ruta = $x.InstallLocation; Tam = [long]$x.InstallSize; Jugado = $null })
        }
        @($j | Sort-Object Tam -Descending)
    }
}
. $FnEspacio

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
        # una carpeta que se borra mientras se recorre (TEMP cambia todo el tiempo) corta Get-ChildItem con
        # "no se encuentra el archivo" y tiraba abajo la Revisión completa: se cuenta lo que se llegó a ver
        $total = 0
        try {
            if ($filtro) { Get-ChildItem -LiteralPath $ruta -Filter $filtro -Force -File | ForEach-Object { $total += $_.Length } }
            else { Get-ChildItem -LiteralPath $ruta -Recurse -Force -File | ForEach-Object { $total += $_.Length } }
        } catch { }
        [math]::Round($total / 1MB, 1)
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

    function Invoke-Accion($a) {
        switch ($a) {
            'limpieza'    { Hacer-Limpieza }
            'juego'       { Hacer-ModoJuego }
            'todo'        {
                Hacer-Limpieza; Out-Line ''; Hacer-ModoJuego; Out-Line ''
                if ($EsAdmin) { Hacer-AjustesJuego; Out-Line '' } else { Out-Line '  Plan de energía y Game Bar: necesitan permisos de administrador.' 'warn'; Out-Line '' }
                Out-Line 'Sistema listo para jugar' 'title'
            }
            'diagnostico' { Hacer-Diagnostico; Hacer-Puntaje }   # "Revisión completa"
            'reparar'     { Hacer-Reparar }
            'red'         { Hacer-Red }
            'router'      { Hacer-ReiniciarRouter $false }
            'routerprobar' { Hacer-ReiniciarRouter $true }
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
[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr proceso);
'@
if (-not ('JVps.Dwm' -as [type])) { Add-Type -Namespace JVps -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int atributo, ref int valor, int tam);' }
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
  <Border x:Name="DBox" Margin="18" CornerRadius="16" Background="{DynamicResource DlgBg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="24,22">
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
        Title="Optimizador" Width="1000" Height="724" MinWidth="980" MinHeight="640"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="False"
        Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI">
  <!-- ventana común (no transparente) con el marco de Windows extendido: la mueve la placa de video y va fluida
       a cualquier Hz; las esquinas redondeadas, la sombra y el desenfoque del Vidrio los pone Windows (Set-MarcoVentana) -->
  <WindowChrome.WindowChrome>
    <WindowChrome GlassFrameThickness="-1" CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <!-- los colores vienen del tema activo (Set-Tema), por eso todo usa DynamicResource -->

    <Style x:Key="Card" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="14" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="18,12">
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

    <!-- botones chicos de las pestañas (Liberar, Analizar) -->
    <Style x:Key="PriSm" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryFg}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="9" Background="{DynamicResource Grad}" Padding="16,8">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecSm" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="Transparent" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="12,5">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
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

  <Border x:Name="Root" Background="{DynamicResource Bg}">
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
          <TextBlock x:Name="TituloVentana" Text="Optimizador Windows" Foreground="{DynamicResource Muted}" FontSize="12" Margin="10,0,0,0"/>
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
          <!-- sesión de Discord: foto y @usuario (solo con sesión iniciada) -->
          <Button x:Name="PerfilChip" Cursor="Hand" Margin="0,0,8,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Sesión de Discord">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="b" CornerRadius="12" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="3,3,10,3">
                  <ContentPresenter/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
            <StackPanel Orientation="Horizontal">
              <Grid Width="18" Height="18">
                <Ellipse x:Name="PerfilFondo" Fill="{DynamicResource Grad}"/>
                <TextBlock x:Name="PerfilInicial" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource PrimaryFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Ellipse x:Name="PerfilFoto" Visibility="Collapsed"/>
              </Grid>
              <TextBlock x:Name="PerfilNombre" FontSize="12" Foreground="{DynamicResource Text}" VerticalAlignment="Center" Margin="7,0,0,0"/>
            </StackPanel>
          </Button>
          <Button x:Name="BtnUpdate" Style="{StaticResource WinBtn}" Content="&#xE895;" FontSize="14" ToolTip="Buscar actualizaciones"/>
          <Button x:Name="BtnTema" Style="{StaticResource WinBtn}" Content="&#xE790;" FontSize="14" ToolTip="Apariencia: color, estilo y tamaño"/>
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
            <StackPanel x:Name="Cabecera" Orientation="Horizontal" Margin="0,0,0,18">
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
                  <Grid x:Name="DiskBar" Height="4" Margin="0,6,0,0"/>
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
                  <TextBlock x:Name="TodoSub" Text="Limpieza, apps de fondo, energía al máximo y Game Bar sin grabar" FontSize="12" Opacity="0.8"/>
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
            <!-- router: aparece solo si es un Movistar Fibra (se puede reiniciar desde acá) -->
            <Border x:Name="RouterFila" Visibility="Collapsed" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="12" Padding="16,6" Margin="0,0,0,12">
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock x:Name="RouterClaveLink" Text="Contraseña" Foreground="{DynamicResource Muted}" FontSize="12" Cursor="Hand" VerticalAlignment="Center" Margin="0,0,14,0" ToolTip="Cambiar la contraseña del router y probarla"/>
                  <Button x:Name="BtnRouter" Style="{StaticResource SecSm}" Content="Reiniciar" ToolTip="Reinicia el router y avisa cuando vuelve internet"/>
                </StackPanel>
                <Grid Width="16" Margin="0,0,12,0" VerticalAlignment="Center">
                  <Ellipse x:Name="RouterPunto" Width="9" Height="9" Fill="{DynamicResource Muted}"/>
                </Grid>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Router" Foreground="{DynamicResource Text}" FontSize="13" FontWeight="SemiBold"/>
                  <TextBlock x:Name="RouterSub" Text="Movistar Fibra · midiendo..." Foreground="{DynamicResource Muted}" FontSize="11.5" TextTrimming="CharacterEllipsis"/>
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
              <StackPanel><DockPanel><TextBlock x:Name="DiagPuntaje" DockPanel.Dock="Right" Text="" FontSize="15" FontWeight="Bold" VerticalAlignment="Top" ToolTip="Puntaje de la última revisión"/><TextBlock Text="&#xE9D9;" Style="{StaticResource Icon}"/></DockPanel><TextBlock Text="Revisión completa" Style="{StaticResource CardTitle}"/><TextBlock x:Name="DiagSub" Text="Puntaje y qué mejorar" Style="{StaticResource CardSub}"/></StackPanel>
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
            <!-- pestañas: Actividad (registro de lo que hace) y Rendimiento (CPU, GPU y RAM en vivo) -->
            <DockPanel DockPanel.Dock="Top">
              <TextBlock x:Name="Pct" DockPanel.Dock="Right" Text="" Foreground="{DynamicResource Muted}" FontSize="12" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="TabAct" Text="Actividad" Foreground="{DynamicResource Text}" FontSize="14" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,14,0"/>
                <TextBlock x:Name="TabRend" Text="Rendimiento" Foreground="{DynamicResource Muted}" FontSize="14" Cursor="Hand" Margin="0,0,14,0"/>
                <TextBlock x:Name="TabPc" Text="Mi PC" Foreground="{DynamicResource Muted}" FontSize="14" Cursor="Hand" Margin="0,0,14,0"/>
                <TextBlock x:Name="TabIni" Text="Arranque" Foreground="{DynamicResource Muted}" FontSize="14" Cursor="Hand" Margin="0,0,14,0" ToolTip="Programas que se abren solos al prender la PC"/>
                <TextBlock x:Name="TabEsp" Text="Espacio" Foreground="{DynamicResource Muted}" FontSize="14" Cursor="Hand" ToolTip="Qué ocupa el disco y qué se puede liberar"/>
              </StackPanel>
            </DockPanel>
            <Grid>
              <DockPanel x:Name="ActPanel">
                <StackPanel DockPanel.Dock="Top">
                  <TextBlock x:Name="Status" Text="Elegí una opción para empezar" Foreground="{DynamicResource Muted}" FontSize="12" Margin="0,6,0,8" TextTrimming="CharacterEllipsis"/>
                  <ProgressBar x:Name="Prog" Minimum="0" Maximum="100" Value="0" Margin="0,0,0,14"/>
                </StackPanel>
                <RichTextBox x:Name="Log" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Text}"
                             FontFamily="Cascadia Mono, Consolas" FontSize="11.5" VerticalScrollBarVisibility="Auto" IsDocumentEnabled="False">
                  <FlowDocument PagePadding="0"/>
                </RichTextBox>
              </DockPanel>
              <ScrollViewer x:Name="RendPanel" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
                <StackPanel>
                  <!-- cada tarjeta: nombre, valor grande, detalle y gráfico del último minuto -->
                  <Border Background="{DynamicResource Panel}" CornerRadius="10" Padding="12,8" Margin="0,0,0,8">
                    <StackPanel>
                      <DockPanel><TextBlock x:Name="RCpuVal" DockPanel.Dock="Right" Text="-" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource Text}"/>
                        <StackPanel><TextBlock Text="CPU" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="RCpuNom" Text="" FontSize="12" Foreground="{DynamicResource Text}" TextTrimming="CharacterEllipsis"/></StackPanel></DockPanel>
                      <TextBlock x:Name="RCpuSub" Text="" FontSize="11" Foreground="{DynamicResource Muted}" Margin="0,1,0,4"/>
                      <Canvas x:Name="GrCpu" Height="30" ClipToBounds="True"><Polygon x:Name="GrCpuFill" Fill="{DynamicResource AccentSoft}"/><Polyline x:Name="GrCpuLine" Stroke="{DynamicResource Accent}" StrokeThickness="1.5"/></Canvas>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource Panel}" CornerRadius="10" Padding="12,8" Margin="0,0,0,8">
                    <StackPanel>
                      <DockPanel><TextBlock x:Name="RGpuVal" DockPanel.Dock="Right" Text="-" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource Text}"/>
                        <StackPanel><TextBlock Text="GPU" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="RGpuNom" Text="" FontSize="12" Foreground="{DynamicResource Text}" TextTrimming="CharacterEllipsis"/></StackPanel></DockPanel>
                      <TextBlock x:Name="RGpuSub" Text="" FontSize="11" Foreground="{DynamicResource Muted}" Margin="0,1,0,4" TextWrapping="Wrap"/>
                      <Canvas x:Name="GrGpu" Height="30" ClipToBounds="True"><Polygon x:Name="GrGpuFill" Fill="{DynamicResource AccentSoft}"/><Polyline x:Name="GrGpuLine" Stroke="{DynamicResource Accent}" StrokeThickness="1.5"/></Canvas>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource Panel}" CornerRadius="10" Padding="12,8" Margin="0,0,0,8">
                    <StackPanel>
                      <DockPanel><TextBlock x:Name="RRamVal" DockPanel.Dock="Right" Text="-" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource Text}"/>
                        <StackPanel><TextBlock Text="MEMORIA" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="RRamNom" Text="" FontSize="12" Foreground="{DynamicResource Text}"/></StackPanel></DockPanel>
                      <TextBlock x:Name="RRamSub" Text="" FontSize="11" Foreground="{DynamicResource Muted}" Margin="0,1,0,4"/>
                      <Canvas x:Name="GrRam" Height="30" ClipToBounds="True"><Polygon x:Name="GrRamFill" Fill="{DynamicResource AccentSoft}"/><Polyline x:Name="GrRamLine" Stroke="{DynamicResource Accent}" StrokeThickness="1.5"/></Canvas>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource Panel}" CornerRadius="10" Padding="12,8">
                    <StackPanel>
                      <TextBlock Text="QUÉ ESTÁ USANDO LA CPU" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Muted}" Margin="0,0,0,6"/>
                      <StackPanel x:Name="RTop"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
              </ScrollViewer>
              <!-- Mi PC: especificaciones (procesador, placa de video, RAM, mother, discos, monitor, Windows, red) -->
              <DockPanel x:Name="PcPanel" Visibility="Collapsed" Margin="0,12,0,0">
                <DockPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                  <TextBlock x:Name="PcCopiar" DockPanel.Dock="Right" Text="Copiar para Discord" Foreground="{DynamicResource Accent}" FontSize="12" Cursor="Hand" VerticalAlignment="Center"/>
                  <TextBlock x:Name="PcEstado" Text="" Foreground="{DynamicResource Muted}" FontSize="12" VerticalAlignment="Center"/>
                </DockPanel>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                  <StackPanel x:Name="PcLista"/>
                </ScrollViewer>
              </DockPanel>
              <!-- Arranque: programas que arrancan con Windows, cada uno con su switch -->
              <DockPanel x:Name="IniPanel" Visibility="Collapsed" Margin="0,12,0,0">
                <StackPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                  <TextBlock x:Name="IniResumen" Text="" Foreground="{DynamicResource Text}" FontSize="13" TextWrapping="Wrap"/>
                  <TextBlock x:Name="IniEstado" Text="Apagarlos no los desinstala: los abrís cuando quieras y se vuelven a prender acá." Foreground="{DynamicResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                </StackPanel>
                <ScrollViewer x:Name="IniScroll" VerticalScrollBarVisibility="Auto">
                  <StackPanel x:Name="IniLista"/>
                </ScrollViewer>
              </DockPanel>
              <!-- Espacio: barra del disco de Windows y tres partes (Limpiar, Juegos, Carpetas) -->
              <DockPanel x:Name="EspPanel" Visibility="Collapsed" Margin="0,12,0,0">
                <StackPanel DockPanel.Dock="Top">
                  <!-- un renglón por disco: usado (color del tema) · lo que se va a liberar (verde, solo en el de Windows) · libre -->
                  <StackPanel x:Name="EspDiscos"/>
                  <TextBlock x:Name="EspLeyenda" FontSize="11" Margin="0,2,0,0"/>
                  <Border CornerRadius="9" Background="{DynamicResource Panel}" Padding="3" HorizontalAlignment="Left" Margin="0,12,0,10">
                    <StackPanel Orientation="Horizontal">
                      <Border x:Name="EspSegLimp" CornerRadius="7" Padding="14,5" Cursor="Hand" Background="Transparent"><TextBlock Text="Limpiar" FontSize="12"/></Border>
                      <Border x:Name="EspSegJue" CornerRadius="7" Padding="14,5" Cursor="Hand" Background="Transparent"><TextBlock Text="Juegos" FontSize="12"/></Border>
                      <Border x:Name="EspSegCarp" CornerRadius="7" Padding="14,5" Cursor="Hand" Background="Transparent"><TextBlock Text="Carpetas" FontSize="12"/></Border>
                    </StackPanel>
                  </Border>
                </StackPanel>
                <Grid>
                  <DockPanel x:Name="EspLimp">
                    <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0">
                      <TextBlock x:Name="EspSel" VerticalAlignment="Center" Foreground="{DynamicResource Muted}" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,0,140,0"/>
                      <ProgressBar x:Name="EspProg" Visibility="Collapsed" HorizontalAlignment="Right" Width="130" Height="6" VerticalAlignment="Center" Minimum="0" Maximum="100"/>
                      <Button x:Name="EspBtnLiberar" Style="{StaticResource PriSm}" HorizontalAlignment="Right" Content="Liberar" IsEnabled="False"/>
                    </Grid>
                    <TextBlock x:Name="EspLimpEstado" DockPanel.Dock="Top" Foreground="{DynamicResource Muted}" FontSize="12" TextWrapping="Wrap"/>
                    <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="EspLista"/></ScrollViewer>
                  </DockPanel>
                  <DockPanel x:Name="EspJue" Visibility="Collapsed">
                    <TextBlock x:Name="EspJueEstado" DockPanel.Dock="Top" Foreground="{DynamicResource Muted}" FontSize="12" TextWrapping="Wrap" Margin="2,0,0,8"/>
                    <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="EspJueLista"/></ScrollViewer>
                  </DockPanel>
                  <DockPanel x:Name="EspCarp" Visibility="Collapsed">
                    <DockPanel DockPanel.Dock="Top">
                      <Button x:Name="EspBtnAnalizar" DockPanel.Dock="Right" Style="{StaticResource SecSm}" Content="Analizar"/>
                      <StackPanel x:Name="EspUnidades" Orientation="Horizontal" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock x:Name="EspCarpEstado" DockPanel.Dock="Top" Foreground="{DynamicResource Muted}" FontSize="11.5" TextWrapping="Wrap" Margin="2,8,0,6"/>
                    <WrapPanel x:Name="EspMigas" DockPanel.Dock="Top" Margin="2,0,0,6"/>
                    <ScrollViewer x:Name="EspCarpScroll" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="EspCarpLista"/></ScrollViewer>
                  </DockPanel>
                </Grid>
              </DockPanel>
            </Grid>
          </DockPanel>
        </Border>
      </Grid>

      <!-- pie -->
      <DockPanel Grid.Row="2" Margin="26,0,26,10">
        <TextBlock x:Name="Footer" Text="Hecho por J.vps · no borra archivos personales" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <StackPanel x:Name="InicioRow" Orientation="Horizontal" Cursor="Hand" Margin="0,0,18,0" Background="Transparent" ToolTip="Al prender la PC se abre solo, sin aviso de permisos">
            <TextBlock Text="Iniciar con Windows" Foreground="{DynamicResource Faint}" FontSize="11" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <Border x:Name="InicioToggle" Width="26" Height="14" CornerRadius="7" VerticalAlignment="Center" Background="{DynamicResource Line}">
              <Ellipse x:Name="InicioDot" Width="10" Height="10" Fill="White" HorizontalAlignment="Left" Margin="2,0"/>
            </Border>
          </StackPanel>
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

# Cristal (vidrio sin desenfoque, se ve todo lo de atrás) necesita ventana transparente por píxel, que Windows no
# deja cambiar después de crearla: se lee el estilo guardado antes y se ajusta el XAML (cambiarlo reabre el programa)
$EstiloInicio = if ($Captura -and $Estilo) { $Estilo } else {
    try { $j0 = Get-Content (Join-Path $Raiz 'config.json') -Raw | ConvertFrom-Json; if ($j0.Discord.Id) { [string]$j0.Estilo } else { '' } } catch { '' } }
if ($EstiloInicio -eq 'Cristal') {
    $s = $xaml.OuterXml -replace 'AllowsTransparency="False"', 'AllowsTransparency="True"' -replace '(?s)<WindowChrome\.WindowChrome>.*?</WindowChrome\.WindowChrome>', ''
    $s = $s -replace 'x:Name="Root"', 'x:Name="Root" CornerRadius="18" BorderThickness="1" BorderBrush="{DynamicResource Line}"'
    $xaml = [xml]$s
}
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
    Rojo      = @{ Nombre = 'Rojo'; A = '#E53935'; B = '#C62828'; Fg = '#FFFFFF' }
    Oceano    = @{ Nombre = 'Océano';     A = '#0EA5E9'; B = '#22D3EE'; Fg = '#04131C' }
    Atardecer = @{ Nombre = 'Atardecer';  A = '#F59E0B'; B = '#EC4899'; Fg = '#1A0F02' }
    Rosa      = @{ Nombre = 'Rosa';       A = '#EC4899'; B = '#A855F7'; Fg = '#FFFFFF' }
    # sin color: vidrio lechoso / blanco y gris. En modo claro el blanco no se lee, ahí usa los grises oscuros (*C)
    Cristal   = @{ Nombre = 'Transparente'; A = '#E5E7EB'; B = '#9CA3AF'; Fg = '#0B0F15'; AC = '#334155'; BC = '#64748B'; FgC = '#FFFFFF' }
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

# estilo: cómo se ve la ventana, aparte del color. Vidrio = paneles translúcidos sobre el fondo de pantalla
# desenfocado; Neón = negro con bordes y brillo del color del tema (siempre oscuro)
$Estilos = [ordered]@{ Solido = 'Sólido'; Vidrio = 'Vidrio esmerilado (desenfoca lo de atrás)'; Cristal = 'Vidrio transparente (se ve todo)'; Neon = 'Neón' }
$Tamanos = [ordered]@{ Completo = 'Completo'; Compacto = 'Compacto' }
$Vidrios = @{
    Oscuro = @{ Panel = '#17FFFFFF'; Line = '#2EFFFFFF'; Hover = '#24FFFFFF'; Pressed = '#30FFFFFF'; LogBg = '#40000000'
                Muted = '#B4BDC9'; Faint = '#8E98A6'; dim = '#8E98A6'; }
    Claro  = @{ Panel = '#73FFFFFF'; Line = '#B3FFFFFF'; Hover = '#A6FFFFFF'; Pressed = '#CCFFFFFF'; LogBg = '#59FFFFFF'
                Muted = '#475569'; Faint = '#64748B'; dim = '#64748B' }
}

# ---------- color personalizado (solo con sesión de Discord) ----------
# el usuario elige un color; el segundo del degradé es el mismo más oscuro y el texto del botón, blanco o negro según cuál se lea
function Get-TemaPersonal([string]$hex = $cfg.ColorPersonal) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($hex)
    $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
    @{ Nombre = 'Personalizado'; A = ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
       B = ('#{0:X2}{1:X2}{2:X2}' -f [int]($c.R * 0.72), [int]($c.G * 0.72), [int]($c.B * 0.72))
       Fg = $(if ($lum -gt 150) { '#0B0F15' } else { '#FFFFFF' }) }
}
function Test-Personal { [bool]$cfg.Discord.Id -and [string]$cfg.ColorPersonal -match '^#[0-9A-Fa-f]{6}$' }
function ConvertFrom-Hsv([double]$h, [double]$s, [double]$v) {
    $c = $v * $s; $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1)); $m = $v - $c
    switch ([int][math]::Floor($h / 60) % 6) {
        0 { $r = $c; $g = $x; $b = 0 } 1 { $r = $x; $g = $c; $b = 0 } 2 { $r = 0; $g = $c; $b = $x }
        3 { $r = 0; $g = $x; $b = $c } 4 { $r = $x; $g = 0; $b = $c } default { $r = $c; $g = 0; $b = $x }
    }
    '#{0:X2}{1:X2}{2:X2}' -f [int](($r + $m) * 255), [int](($g + $m) * 255), [int](($b + $m) * 255)
}
function ConvertTo-Hsv($c) {
    $r = [double]$c.R / 255; $g = [double]$c.G / 255; $b = [double]$c.B / 255   # [double]: 0/255 da [int] y Max(int, double) redondeaba
    $mx = [math]::Max($r, [math]::Max($g, $b)); $mn = [math]::Min($r, [math]::Min($g, $b)); $d = $mx - $mn
    $h = if ($d -eq 0) { 0 } elseif ($mx -eq $r) { 60 * ((($g - $b) / $d) % 6) } elseif ($mx -eq $g) { 60 * ((($b - $r) / $d) + 2) } else { 60 * ((($r - $g) / $d) + 4) }
    if ($h -lt 0) { $h += 360 }
    @($h, $(if ($mx -eq 0) { 0 } else { $d / $mx }), $mx)
}
function New-Degrade([string]$a, [string]$b) {
    (New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($a)), ([Windows.Media.ColorConverter]::ConvertFromString($b)), 0).psobject.BaseObject
}
function Update-ColorPersonal([string]$hex, [string]$desde) {
    $p = $script:Cp
    if ($p.Ocupado) { return }
    $p.Ocupado = $true
    try {
        $t = Get-TemaPersonal $hex
        $p.Hex = $t.A
        if ($desde -ne 'barras') { $hsv = ConvertTo-Hsv ([Windows.Media.ColorConverter]::ConvertFromString($t.A)); $p.H.Value = $hsv[0]; $p.S.Value = $hsv[1]; $p.V.Value = $hsv[2] }
        if ($desde -ne 'texto') { $p.Texto.Text = $t.A }
        # las barras de saturación y brillo muestran hacia dónde va el color con el tono elegido
        $p.FondoS.Background = New-Degrade (ConvertFrom-Hsv $p.H.Value 0 $p.V.Value) (ConvertFrom-Hsv $p.H.Value 1 $p.V.Value)
        $p.FondoV.Background = New-Degrade '#000000' (ConvertFrom-Hsv $p.H.Value $p.S.Value 1)
        $p.Muestra.Background = New-Degrade $t.A $t.B
        $p.MuestraTxt.Foreground = $bc.ConvertFromString($t.Fg)
        $p.AppPend = $true   # la ventana grande la repinta el reloj del selector, sin apuro
    } catch { } finally { $p.Ocupado = $false }
}
# barra del selector: sin el riel azul de Windows, solo un círculo blanco sobre el degradé (clic en cualquier lado lo lleva ahí)
$EstiloBarra = [Windows.Markup.XamlReader]::Parse(@'
<Style TargetType="Slider" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
  <Setter Property="Height" Value="20"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="Slider">
      <Track Name="PART_Track">
        <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton>
        <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton>
        <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
          <Ellipse Width="18" Height="18" Fill="White" Stroke="#59000000" StrokeThickness="1.5"/>
        </ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
      </Track>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
'@)
function Show-ColorPersonal {
    $d = New-Dialogo 'Color personalizado' 'Elegí el color con las barras, tocá uno de los de abajo o pegá un código (#RRGGBB).' 'Usar' 'Cancelar' 'info'
    $script:Cp = @{ Ocupado = $false; Hex = '' }
    $cont = New-Object Windows.Controls.StackPanel; $cont.Margin = '0,16,0,0'
    # vista previa: el botón grande con el color elegido
    $m = New-Object Windows.Controls.Border; $m.Height = 42; $m.CornerRadius = 10; $m.Margin = '0,0,0,14'
    $mt = New-Object Windows.Controls.TextBlock; $mt.Text = 'Así se ve'; $mt.FontWeight = 'SemiBold'; $mt.FontSize = 14
    $mt.HorizontalAlignment = 'Center'; $mt.VerticalAlignment = 'Center'; $m.Child = $mt
    [void]$cont.Children.Add($m); $script:Cp.Muestra = $m; $script:Cp.MuestraTxt = $mt
    # barras: tono (arcoíris), saturación y brillo, cada una con su fondo
    foreach ($b in @(@('Tono', 'H', 360), @('Intensidad', 'S', 1), @('Brillo', 'V', 1))) {
        $et = New-Object Windows.Controls.TextBlock; $et.Text = $b[0]; $et.FontSize = 12; $et.Margin = '0,0,0,4'
        $et.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Muted')
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,0,0,10'
        $f = New-Object Windows.Controls.Border; $f.Height = 10; $f.CornerRadius = 5; $f.Margin = '5,0'; $f.VerticalAlignment = 'Center'
        $s = New-Object Windows.Controls.Slider; $s.Minimum = 0; $s.Maximum = $b[2]; $s.VerticalAlignment = 'Center'
        $s.Style = $EstiloBarra; $s.IsMoveToPointEnabled = $true; $s.Cursor = 'Hand'
        $s.Add_ValueChanged({ $script:Cp.Pend = $true })
        [void]$g.Children.Add($f); [void]$g.Children.Add($s)
        [void]$cont.Children.Add($et); [void]$cont.Children.Add($g)
        $script:Cp[$b[1]] = $s; $script:Cp['Fondo' + $b[1]] = $f
    }
    $arco = New-Object Windows.Media.LinearGradientBrush; $arco.StartPoint = '0,0'; $arco.EndPoint = '1,0'
    foreach ($i in 0..6) { $arco.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString((ConvertFrom-Hsv ($i * 60 % 360) 1 1))), ($i / 6))) }
    $script:Cp.FondoH.Background = $arco.psobject.BaseObject
    # colores rápidos
    $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,4,0,8'
    foreach ($hex in '#E53935', '#FB8C00', '#FDD835', '#43A047', '#00ACC1', '#1E88E5', '#3949AB', '#8E24AA', '#D81B60', '#6D4C41', '#78909C', '#F5F5F5') {
        $o = New-Object Windows.Controls.Border; $o.Width = 26; $o.Height = 26; $o.CornerRadius = 13; $o.Margin = '0,0,8,8'
        $o.Background = $bc.ConvertFromString($hex); $o.Cursor = 'Hand'; $o.Tag = $hex; $o.BorderThickness = 1
        $o.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
        $o.Add_MouseLeftButtonUp({ Update-ColorPersonal $this.Tag 'muestra' })
        [void]$wp.Children.Add($o)
    }
    [void]$cont.Children.Add($wp)
    $tb = New-Object Windows.Controls.TextBox; $tb.Padding = '10,7'; $tb.FontSize = 14; $tb.MaxLength = 7; $tb.BorderThickness = 1; $tb.FontFamily = 'Consolas'
    $tb.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'LogBg')
    $tb.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $tb.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line')
    $tb.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Text')
    $tb.Add_TextChanged({ $x = $this.Text.Trim(); if ($x -notmatch '^#') { $x = '#' + $x }; if ($x -match '^#[0-9A-Fa-f]{6}$') { Update-ColorPersonal $x 'texto' } })
    [void]$cont.Children.Add($tb); $script:Cp.Texto = $tb
    $d.FindName('DTexto').Parent.Parent.Children.Insert(2, $cont)
    $inicio = if (Test-Personal) { $cfg.ColorPersonal } else { (Get-TemaActual).A }
    Update-ColorPersonal $inicio ''
    # un reloj junta los movimientos: el selector se actualiza hasta 60 veces por segundo y la app entera (solo los
    # colores, Set-Tema inicial: ~20 ms más repintar la ventana) unas 8, así la barra no se traba al arrastrarla
    $antes = @{ Tema = $cfg.Tema; Color = $cfg.ColorPersonal }
    $script:Cp.AppPend = $false; $script:Cp.AppUlt = [datetime]::MinValue
    $vivo = New-Object Windows.Threading.DispatcherTimer; $vivo.Interval = [TimeSpan]::FromMilliseconds(16)
    $vivo.Add_Tick({
        $p = $script:Cp
        if ($p.Pend) { $p.Pend = $false; Update-ColorPersonal (ConvertFrom-Hsv $p.H.Value $p.S.Value $p.V.Value) 'barras' }
        if ($p.AppPend -and ((Get-Date) - $p.AppUlt).TotalMilliseconds -ge 120) {
            $p.AppPend = $false; $p.AppUlt = Get-Date
            $cfg.ColorPersonal = $p.Hex; Set-Tema 'Personal' ([bool]$cfg.Claro) $true
        }
    })
    $vivo.Start()
    $script:Cp.Vivo = $vivo
    $ok = $d.ShowDialog() -and $script:Cp.Hex
    if ($script:Cp.Pend) { Update-ColorPersonal (ConvertFrom-Hsv $script:Cp.H.Value $script:Cp.S.Value $script:Cp.V.Value) 'barras' }
    $vivo.Stop(); $script:Cp.Vivo = $null
    if ($ok) { $cfg.ColorPersonal = $script:Cp.Hex; Set-Tema 'Personal' ([bool]$cfg.Claro); return }
    # canceló: vuelve a como estaba
    $cfg.ColorPersonal = $antes.Color
    Set-Tema $antes.Tema ([bool]$cfg.Claro)
}
function Get-TemaActual { if ($cfg.Tema -eq 'Personal' -and (Test-Personal)) { Get-TemaPersonal } elseif ($Temas.Contains([string]$cfg.Tema)) { $Temas[[string]$cfg.Tema] } else { $Temas.Esmeralda } }

# ---------- inicio de sesión con Discord ----------
# OAuth2 "implicit": Discord devuelve el token en la dirección y no hace falta ningún secreto dentro de la app.
# El navegador vuelve a http://localhost:<puerto>/discord, donde escucha el optimizador. Solo pide "identify"
# (nombre y avatar): nada de mensajes ni servidores.
$DiscordAppId = '1566271836415594536'   # Client ID de la aplicación en discord.com/developers (Redirects: http://localhost:53682/discord)
$DiscordPuerto = 53682
function Start-LoginDiscord([scriptblock]$luego) {
    if (-not $DiscordAppId) { [void](Show-Dialogo 'Todavía no disponible' 'El inicio de sesión con Discord todavía no está activado en esta versión.'); return }
    if ($script:Login) { Stop-LoginDiscord }
    $l = New-Object Net.HttpListener
    $l.Prefixes.Add("http://localhost:$DiscordPuerto/")
    try { $l.Start() } catch { [void](Show-Dialogo 'No se pudo iniciar sesión' "Otro programa está usando el puerto $DiscordPuerto. Cerralo y probá de nuevo." 'Aceptar' '' 'alerta'); return }
    $estado = [guid]::NewGuid().ToString('N')
    $redir = [uri]::EscapeDataString("http://localhost:$DiscordPuerto/discord")
    Start-Process "https://discord.com/oauth2/authorize?client_id=$DiscordAppId&response_type=token&redirect_uri=$redir&scope=identify&state=$estado"
    $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:Login = @{ L = $l; Estado = $estado; Tarea = $l.GetContextAsync(); Hasta = (Get-Date).AddMinutes(3); Luego = $luego; Timer = $t }
    $t.Add_Tick({ Step-LoginDiscord })
    $t.Start()
}
function Stop-LoginDiscord {
    if (-not $script:Login) { return }
    $script:Login.Timer.Stop()
    try { $script:Login.L.Stop(); $script:Login.L.Close() } catch { }
    $script:Login = $null
}
function Step-LoginDiscord {
    $s = $script:Login
    if (-not $s) { return }
    if ((Get-Date) -gt $s.Hasta) { Stop-LoginDiscord; return }   # no volvió del navegador en 3 minutos
    if (-not $s.Tarea.IsCompleted) { return }
    $ctx = try { $s.Tarea.Result } catch { $null }
    if (-not $ctx) { Stop-LoginDiscord; return }
    $ruta = $ctx.Request.Url.AbsolutePath; $q = $ctx.Request.QueryString
    $fin = $false; $ok = $false; $codigo = 200
    $pagina = { param($titulo, $texto) "<!doctype html><meta charset=utf-8><title>Optimizador</title><body style=""margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#0D1117;color:#E6EDF3;font-family:Segoe UI,sans-serif;text-align:center""><div><h2 style=""margin:0 0 8px"">$titulo</h2><p style=""color:#8B95A3;margin:0"">$texto</p></div>" }
    if ($ruta -eq '/discord') {
        # el token viene después del # y el navegador no se lo manda al servidor: esta página lo reenvía como ?...
        $html = "<!doctype html><meta charset=utf-8><script>location.replace('/listo?'+(location.hash.substring(1)||location.search.substring(1)))</script>"
    } elseif ($ruta -eq '/listo') {
        $fin = $true
        if ($q['state'] -eq $s.Estado -and $q['access_token']) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                $u = Invoke-RestMethod 'https://discord.com/api/v10/users/@me' -Headers @{ Authorization = "Bearer $($q['access_token'])" } -TimeoutSec 10
                $nombre = if ($u.global_name) { [string]$u.global_name } else { [string]$u.username }
                $cfg.Discord = @{ Id = [string]$u.id; Nombre = $nombre; Usuario = [string]$u.username; Avatar = [string]$u.avatar }
                Save-Cfg
                $ok = $true
            } catch { Log-Archivo "Discord: $($_.Exception.Message)" }
        }
        $html = if ($ok) { & $pagina "Listo, $([Net.WebUtility]::HtmlEncode($cfg.Discord.Nombre))" 'Ya podés cerrar esta pestaña y volver al Optimizador.' }
                elseif ($q['error']) { & $pagina 'Cancelaste el inicio de sesión' 'Podés cerrar esta pestaña.' }
                else { & $pagina 'No se pudo iniciar sesión' 'Cerrá esta pestaña y probá de nuevo desde el Optimizador.' }
    } else { $codigo = 404; $html = '' }   # favicon y demás
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.StatusCode = $codigo; $ctx.Response.ContentType = 'text/html; charset=utf-8'
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
    } catch { }
    if (-not $fin) { $s.Tarea = $s.L.GetContextAsync(); return }
    Stop-LoginDiscord
    if ($ok) { Set-PerfilUI; Show-Main; if ($s.Luego) { & $s.Luego } }
    elseif (-not $q['error']) { Show-Main; [void](Show-Dialogo 'No se pudo iniciar sesión' 'Discord no confirmó la cuenta. Probá de nuevo en un rato.' 'Aceptar' '' 'alerta') }
}
# chip de arriba: foto de Discord (la baja sola el BitmapImage; mientras tanto o sin internet, la inicial) y @usuario
function Set-PerfilUI {
    if (Get-Command Set-RouterUI -ErrorAction SilentlyContinue) { Set-RouterUI }   # el router es solo con sesión
    if (-not $cfg.Discord.Id) { $ui.PerfilChip.Visibility = 'Collapsed'; return }
    $usuario = if ($cfg.Discord.Usuario) { [string]$cfg.Discord.Usuario } else { [string]$cfg.Discord.Nombre }
    $ui.PerfilNombre.Text = '@' + $usuario
    $ui.PerfilInicial.Text = if ($usuario) { $usuario.Substring(0, 1).ToUpper() } else { '?' }
    $ui.PerfilChip.ToolTip = "Sesión de Discord: $($cfg.Discord.Nombre)"
    $ui.PerfilFoto.Visibility = 'Collapsed'
    $ui.PerfilChip.Visibility = 'Visible'
    # sin foto propia, Discord usa uno de sus 6 avatares por defecto según el id
    $url = if ($cfg.Discord.Avatar) { "https://cdn.discordapp.com/avatars/$($cfg.Discord.Id)/$($cfg.Discord.Avatar).png?size=64" }
           else { "https://cdn.discordapp.com/embed/avatars/$((([uint64]$cfg.Discord.Id) -shr 22) % 6).png" }
    # ya bajada antes: queda en la PC con el código de la foto en el nombre (si la cambia en Discord, cambia el código)
    $clave = if ($cfg.Discord.Avatar) { [string]$cfg.Discord.Avatar } else { 'defecto' }
    $script:PerfilArchivo = Join-Path $Raiz "avatar_$clave.png"
    try {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.DecodePixelWidth = 36
        if (Test-Path -LiteralPath $script:PerfilArchivo) { $bi.CacheOption = 'OnLoad'; $bi.UriSource = [uri]$script:PerfilArchivo }
        else { $bi.UriSource = [uri]$url }
        $bi.EndInit()
        # la referencia la mantiene viva: sin ella la limpieza de memoria (al ir a la bandeja) la tiraba a mitad de la descarga
        $script:PerfilBi = $bi
        if ($bi.IsDownloading) {
            $bi.Add_DownloadCompleted({ Set-PerfilFoto $this $true })
            $bi.Add_DownloadFailed({ Log-Archivo "Discord: no bajó la foto ($($_.ErrorException.Message))"; $script:PerfilBi = $null })
        } else { Set-PerfilFoto $bi $false }
    } catch { Log-Archivo "Discord: foto ($($_.Exception.Message))" }
}
function Set-PerfilFoto($bi, [bool]$guardar) {
    $br = New-Object Windows.Media.ImageBrush $bi; $br.Stretch = 'UniformToFill'
    $ui.PerfilFoto.Fill = $br; $ui.PerfilFoto.Visibility = 'Visible'
    $script:PerfilBi = $null
    if (-not $guardar) { return }
    try {
        Get-ChildItem -LiteralPath $Raiz -Filter 'avatar_*.png' | Remove-Item -Force   # la foto anterior, si la cambió
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bi))
        $fs = [IO.File]::Create($script:PerfilArchivo); $enc.Save($fs); $fs.Close()
    } catch { }
}
function Show-MenuPerfil {
    $e = @(@{ T = 'head'; Texto = 'DISCORD' })
    $e += @{ T = 'info'; Texto = "$($cfg.Discord.Nombre)  ·  @$($cfg.Discord.Usuario)" }
    $e += @{ T = 'sep' }
    $e += @{ T = 'item'; Texto = 'Elegir color personalizado'; A = { Use-ColorPersonal } }
    $e += @{ T = 'item'; Texto = 'Cerrar sesión'; A = { Exit-Discord } }
    Show-Menu $e
}
function Request-Discord([string]$para, [scriptblock]$luego) {
    $txt = "Para $para tenés que iniciar sesión con Discord.`n`n" +
           "Se abre la página oficial de Discord (discord.com) con la aplicación `"Optimizador J.vps`". Ahí vas a ver que solo pide tu nombre de usuario y tu foto: nada de mensajes, servidores ni contraseña. Tocás Autorizar y volvés acá.`n`n" +
           "Si Discord te pide la contraseña, fijate que la dirección arriba diga discord.com. Podés sacarle el permiso cuando quieras en Discord > Ajustes > Aplicaciones autorizadas."
    if (Show-Dialogo 'Iniciar sesión con Discord' $txt 'Iniciar sesión' 'Cancelar' 'escudo') { Start-LoginDiscord $luego }
}
function Use-ColorPersonal {
    if (-not $cfg.Discord.Id) { Request-Discord 'elegir tu propio color' { Show-ColorPersonal }; return }
    Show-ColorPersonal
}
function Exit-Discord {
    $cfg.Discord = $null
    Get-ChildItem -LiteralPath $Raiz -Filter 'avatar_*.png' | Remove-Item -Force
    if ($cfg.Tema -eq 'Personal' -or $cfg.Tema -in $TemasDiscord) { $cfg.Tema = 'Esmeralda' }
    # el vidrio transparente es otro tipo de ventana: para volver a Sólido hay que reabrir
    if ($win.AllowsTransparency) { Save-Cfg; [void](Show-Dialogo 'Sesión cerrada' 'El vidrio transparente es solo con sesión de Discord: el Optimizador se cierra y se abre solo con el estilo Sólido.'); Start-Reabrir; return }
    Set-PerfilUI
    Set-Tema $cfg.Tema ([bool]$cfg.Claro)   # sin sesión, el vidrio esmerilado pasa a Sólido
}

function Set-Tema([string]$nombre, [bool]$claro, [bool]$inicial = $false) {
    # el personalizado es solo con sesión de Discord: sin sesión vuelve al de siempre
    if ($nombre -eq 'Personal' -and (Test-Personal)) { $t = Get-TemaPersonal }
    else {
        # el Transparente también es solo con sesión
        if (-not $Temas.Contains($nombre) -or ($nombre -in $TemasDiscord -and -not $cfg.Discord.Id)) { $nombre = 'Esmeralda' }
        $t = $Temas[$nombre]
    }
    $estilo = Get-EstiloUsable
    if ($estilo -eq 'Neon') { $claro = $false }
    if ($claro -and $t.AC) { $t = @{ Nombre = $t.Nombre; A = $t.AC; B = $t.BC; Fg = $t.FgC } }
    $base = if ($claro) { $Bases.Claro.Clone() } else { $Bases.Oscuro.Clone() }
    $R = $app.Resources
    $R['DlgBg'] = $bc.ConvertFromString($base.Panel)   # los carteles quedan siempre sólidos
    if ($estilo -in 'Vidrio', 'Cristal') {
        $v = if ($claro) { $Vidrios.Claro } else { $Vidrios.Oscuro }
        foreach ($k in 'Panel', 'Line', 'Hover', 'Pressed', 'LogBg', 'Muted', 'Faint', 'dim') { $base[$k] = $v[$k] }
        # menú de la bandeja: el mismo vidrio (Windows lo desenfoca, ver Set-MarcoVentana)
        $base.MenuBg = if ($t.Nombre -eq 'Transparente') { if ($claro) { '#1AFFFFFF' } else { '#0A000000' } }
                       elseif ($claro) { '#4DF4F6F9' } else { '#40' + $t.A.Substring(1) }
        $base.MenuLine = if ($claro) { '#1A000000' } else { '#2EFFFFFF' }
        $base.MenuHover = if ($claro) { '#80FFFFFF' } else { '#26FFFFFF' }
    } elseif ($estilo -eq 'Neon') {
        $hex = $t.A.Substring(1)
        $base.Bg = '#050608'; $base.Panel = '#0A0C10'; $base.LogBg = '#030405'
        $base.Line = '#59' + $hex; $base.Hover = '#1A' + $hex; $base.Pressed = '#2B' + $hex
        $base.MenuBg = '#0A0C10'; $base.MenuLine = '#59' + $hex; $base.MenuHover = '#22' + $hex
    }
    foreach ($k in 'Bg', 'Panel', 'Line', 'Text', 'Muted', 'Faint', 'Hover', 'Pressed', 'LogBg', 'OvBg', 'MenuBg', 'MenuLine') {
        $R[$k] = $bc.ConvertFromString($base[$k])
    }
    if ($estilo -in 'Vidrio', 'Cristal') {
        # liquid glass: canto brillante (fuerte arriba a la izquierda y abajo a la derecha, apagado en el medio)
        # y el vidrio un poco más claro arriba, como si le pegara la luz
        $deg = {
            param($paradas, $x2, $y2)
            $g = New-Object Windows.Media.LinearGradientBrush
            $g.StartPoint = New-Object Windows.Point 0, 0; $g.EndPoint = New-Object Windows.Point $x2, $y2
            foreach ($p in $paradas) { $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($p[0])), $p[1])) }
            $g.Freeze(); $g.psobject.BaseObject
        }
        if ($claro) {
            $R['Panel'] = & $deg @(@('#B3FFFFFF', 0), @('#59FFFFFF', 1)) 0 1
            $R['Hover'] = & $deg @(@('#E6FFFFFF', 0), @('#8CFFFFFF', 1)) 0 1
            $R['Line'] = & $deg @(@('#FFFFFFFF', 0), @('#73FFFFFF', 0.35), @('#40FFFFFF', 0.65), @('#E6FFFFFF', 1)) 1 1
        } else {
            # oscuro abajo y apenas claro arriba: un relleno blanco sobre vidrio teñido lo lavaba (rojo -> rosa)
            $R['Panel'] = & $deg @(@('#12FFFFFF', 0), @('#33000000', 1)) 0 1
            $R['Hover'] = & $deg @(@('#24FFFFFF', 0), @('#1A000000', 1)) 0 1
            $R['Line'] = & $deg @(@('#B3FFFFFF', 0), @('#26FFFFFF', 0.35), @('#12FFFFFF', 0.65), @('#73FFFFFF', 1)) 1 1
        }
        if ($estilo -eq 'Cristal') {
            # vidrio claro como una placa: blanquecino, se ve todo lo de atrás; el registro más tapado para leerlo
            if ($claro) {
                $R['Panel'] = & $deg @(@('#59FFFFFF', 0), @('#2EFFFFFF', 1)) 0 1
                $R['LogBg'] = $bc.ConvertFromString('#99FFFFFF')
            } else {
                $R['Panel'] = & $deg @(@('#26FFFFFF', 0), @('#0FFFFFFF', 1)) 0 1
                $R['Hover'] = & $deg @(@('#40FFFFFF', 0), @('#1AFFFFFF', 1)) 0 1
                $R['LogBg'] = $bc.ConvertFromString('#80000000')
            }
        }
    }
    $R['Accent'] = $bc.ConvertFromString($t.A)
    $R['Accent2'] = $bc.ConvertFromString($t.B)
    $R['PrimaryFg'] = $bc.ConvertFromString($t.Fg)
    $R['AccentSoft'] = $bc.ConvertFromString(('#26' + $t.A.Substring(1)))
    $R['AccentLine'] = $bc.ConvertFromString(('#44' + $t.A.Substring(1)))
    # datos en pantalla: va arriba de los juegos y nunca tiene el foco, y Windows no desenfoca ventanas sin foco,
    # así que el Vidrio ahí es el mismo look sin desenfoque (más tapado, para que se lea sobre cualquier juego)
    $R['OvLine'] = $R['AccentLine']
    if ($estilo -in 'Vidrio', 'Cristal') {
        $ov1 = New-Object Windows.Media.LinearGradientBrush
        $ov1.StartPoint = New-Object Windows.Point 0, 0; $ov1.EndPoint = New-Object Windows.Point 1, 1
        $paradas = if ($claro) { @(@(('#66' + $t.A.Substring(1)), 0), @('#D9F4F6F9', 0.5), @(('#59' + $t.B.Substring(1)), 1)) }
                   else { @(@(('#8C' + $t.A.Substring(1)), 0), @('#CC0B0F15', 0.5), @(('#80' + $t.B.Substring(1)), 1)) }
        foreach ($p in $paradas) { $ov1.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($p[0])), $p[1])) }
        $R['OvBg'] = $ov1.psobject.BaseObject
        $R['OvLine'] = $R['Line']   # el canto brillante del vidrio
    } elseif ($estilo -eq 'Neon') {
        $R['OvBg'] = $bc.ConvertFromString('#EE050608')
        $R['OvLine'] = $bc.ConvertFromString(('#CC' + $t.A.Substring(1)))
    }
    $grad = New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($t.A)), ([Windows.Media.ColorConverter]::ConvertFromString($t.B)), (New-Object Windows.Point 0, 0), (New-Object Windows.Point 1, 1)
    # .BaseObject: New-Object lo envuelve en un PSObject y WPF no lo reconoce como pincel
    $R['Grad'] = $grad.psobject.BaseObject

    foreach ($k in 'info', 'ok', 'warn', 'err', 'dim') { $Colores[$k] = $bc.ConvertFromString($base[$k]) }
    if ($estilo -in 'Vidrio', 'Cristal' -and -not $claro) {
        # sobre vidrio teñido del mismo color, el acento puro no se lee (rojo sobre rojo): textos e íconos más claros
        $aclarar = { param($hex, $f) $c = [Windows.Media.ColorConverter]::ConvertFromString($hex)
            $bc.ConvertFromString(('#{0:X2}{1:X2}{2:X2}' -f [int]($c.R + (255 - $c.R) * $f), [int]($c.G + (255 - $c.G) * $f), [int]($c.B + (255 - $c.B) * $f))) }
        # poquito: mezclar con blanco lo lleva al pastel (el rojo se volvía rosa). El segundo color del degradé suele
        # ser oscuro (Rojo: más oscuro), así que los títulos del registro usan el mismo acento aclarado
        $R['Accent'] = & $aclarar $t.A 0.08
        $R['Accent2'] = $R['Accent']
    }
    $Colores.title = if ($claro) { $R['Accent'] } else { $R['Accent2'] }
    $Colores.accent = $R['Accent']
    $Colores.text = $R['Text']; $Colores.muted = $R['Muted']
    $Colores.hover = $bc.ConvertFromString($base.MenuHover); $Colores.menuLine = $R['MenuLine']
    $Colores.toggleOff = $bc.ConvertFromString($base.ToggleOff); $Colores.warnSoft = $bc.ConvertFromString($base.WarnSoft)

    $cfg.Tema = $nombre; $cfg.Claro = $claro
    Set-EstiloVentana $estilo $claro $t
    if ($inicial) { return }
    # repinta lo que el código ya había coloreado
    foreach ($p in $ui.Log.Document.Blocks) { foreach ($r in $p.Inlines) { if ($r.Tag) { $r.Foreground = $Colores[$r.Tag] } } }
    Apply-Admin
    Update-Stats
    $ui.BtnOverlay.Foreground = if ($ov.IsVisible) { $Colores.accent } else { $Colores.muted }
    $ui.BtnUpdate.Foreground = if ($script:UpdPendiente) { $Colores.accent } else { $Colores.muted }
    if (Get-Command Set-AutoUI -ErrorAction SilentlyContinue) { Set-AutoUI }   # los interruptores toman el color del tema
    if (Get-Command Set-InicioUI -ErrorAction SilentlyContinue) { Set-InicioUI }
    if (Get-Command Set-PuntajeUI -ErrorAction SilentlyContinue) { Set-PuntajeUI }
    if (Get-Command Set-Tab -ErrorAction SilentlyContinue) { Set-Tab $script:Pestana }
    if ($ov.IsVisible) { Update-Overlay }
    Save-Cfg
}

# ---------- estilo de la ventana ----------
# Lo hace Windows 11 (DWM): desenfoque acrílico de lo que hay detrás, esquinas redondeadas, borde de color y modo oscuro
# del marco. En Windows 10 no hay acrílico: el Vidrio queda casi sólido para que se pueda leer.
$script:ConAcrilico = [Environment]::OSVersion.Version.Build -ge 22621
function Set-MarcoVentana([string]$estilo, [bool]$claro, $t, $ventana = $win) {
    if ($ventana.AllowsTransparency) { return }   # Cristal: la dibuja WPF entera, sin marco de Windows
    if ($estilo -eq 'Cristal') { $estilo = 'Vidrio' }   # el menú, que sí tiene marco, va con el vidrio desenfocado
    $h = (New-Object Windows.Interop.WindowInteropHelper $ventana).Handle
    if ($h -eq [IntPtr]::Zero) { return }   # todavía no existe: lo vuelve a llamar SourceInitialized
    [Windows.Interop.HwndSource]::FromHwnd($h).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
    $set = { param($attr, $val) $v = [int]$val; try { [void][JVps.Dwm]::DwmSetWindowAttribute($h, $attr, [ref]$v, 4) } catch { } }
    & $set 20 ([int](-not $claro))   # marco oscuro / claro
    & $set 33 2                      # esquinas redondeadas
    # borde: color de las líneas del tema, o el del acento en Neón (COLORREF = 0x00BBGGRR)
    $c = if ($estilo -eq 'Neon') { [Windows.Media.ColorConverter]::ConvertFromString($t.A) } else { $app.Resources['Line'].Color }
    if ($estilo -eq 'Vidrio') { $c = [Windows.Media.Color]::FromRgb(0x5A, 0x60, 0x6A); if ($claro) { $c = [Windows.Media.Color]::FromRgb(0xFF, 0xFF, 0xFF) } }
    & $set 34 ([int]$c.R -bor ([int]$c.G -shl 8) -bor ([int]$c.B -shl 16))
    & $set 38 $(if ($estilo -eq 'Vidrio' -and $script:ConAcrilico) { 3 } else { 1 })   # 3 = acrílico, 1 = nada
}
function Set-EstiloVentana([string]$estilo, [bool]$claro, $t) {
    $script:EstiloActual = @($estilo, $claro, $t)
    if ($estilo -eq 'Cristal') {
        # casi nada: lo justo para que la ventana se pueda agarrar entre los paneles
        $ui.Root.Background = $bc.ConvertFromString($(if ($claro) { '#1AFFFFFF' } else { '#14000000' }))
    } elseif ($estilo -eq 'Vidrio') {
        # tinte por encima del desenfoque de Windows: lo justo para que el texto se lea sobre cualquier fondo
        if (-not $script:ConAcrilico) {
            $ui.Root.Background = $bc.ConvertFromString($(if ($claro) { '#F2F4F6F9' } else { '#F20D1117' }))
        } elseif ($t.Nombre -eq 'Transparente') {
            $ui.Root.Background = $bc.ConvertFromString($(if ($claro) { '#14FFFFFF' } else { '#0A000000' }))
        } else {
            # vidrio teñido con los colores del tema (en diagonal, del principal al segundo), no gris
            $a1 = if ($claro) { '#33' } else { '#59' }; $a2 = if ($claro) { '#26' } else { '#4D' }
            $g = New-Object Windows.Media.LinearGradientBrush
            $g.StartPoint = New-Object Windows.Point 0, 0; $g.EndPoint = New-Object Windows.Point 1, 1
            $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($a1 + $t.A.Substring(1))), 0))
            $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($(if ($claro) { '#1AFFFFFF' } else { '#4D0B0F15' }))), 0.5))
            $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($a2 + $t.B.Substring(1))), 1))
            $ui.Root.Background = $g.psobject.BaseObject
        }
    } else {
        $ui.Root.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Bg')
    }
    Set-MarcoVentana $estilo $claro $t
    if ($menuWin) { Set-MarcoVentana $estilo $claro $t $menuWin }
    # Neón: el botón grande brilla con el color del tema
    if ($estilo -eq 'Neon') {
        $sh = New-Object Windows.Media.Effects.DropShadowEffect
        $sh.Color = [Windows.Media.ColorConverter]::ConvertFromString($t.A); $sh.BlurRadius = 26; $sh.ShadowDepth = 0; $sh.Opacity = 0.75
        $ui.BtnTodo.Effect = $sh
    } else { $ui.BtnTodo.Effect = $null }
}
$win.Add_SourceInitialized({ if ($script:EstiloActual) { Set-MarcoVentana @script:EstiloActual } })

# ---------- tamaño: Compacto saca la cabecera grande y los textos de abajo de cada botón ----------
function Set-Tamano([string]$tam, [bool]$inicial = $false) {
    if (-not $Tamanos.Contains($tam)) { $tam = 'Completo' }
    $cfg.Tamano = $tam
    $compacto = $tam -eq 'Compacto'
    $vis = if ($compacto) { 'Collapsed' } else { 'Visible' }
    $ui.Cabecera.Visibility = $vis
    $ui.TodoSub.Visibility = $vis
    $sub = $win.Resources['CardSub']
    foreach ($n in 'BtnLimpieza', 'BtnJuego', 'BtnRed', 'BtnDiag', 'BtnReparar', 'BtnRestaurar') {
        foreach ($tb in $ui[$n].Content.Children) { if ($tb.Style -eq $sub) { $tb.Visibility = $vis } }
    }
    # en compacto se ve la versión arriba, porque la cabecera que la mostraba no está
    $ui.TituloVentana.Text = if ($compacto) { "Optimizador J.vps  ·  v$Version" } else { 'Optimizador Windows' }
    # más angosto o más bajo no entran los títulos de los botones
    $win.MinHeight = if ($compacto) { 600 } else { 640 }
    if (-not $inicial -or $compacto) { $win.Height = if ($compacto) { 630 } else { 724 } }
    # más angosto que 980 se cortan los títulos de los botones (ventanas achicadas antes de la 3.41)
    if ($win.Width -lt 1000) { $win.Width = 1000 }
    if (-not $inicial) { Save-Cfg }
}

# los dos vidrios son solo con sesión de Discord: sin sesión se ve Sólido (lo guardado no se pierde)
$EstilosDiscord = @('Vidrio', 'Cristal')
$TemasDiscord = @('Cristal')   # el color Transparente
function Set-TemaPedido([string]$k) {
    if ($k -in $TemasDiscord -and -not $cfg.Discord.Id) { Request-Discord 'usar el color Transparente' ([scriptblock]::Create("Set-Tema '$k' `$cfg.Claro")); return }
    Set-Tema $k ([bool]$cfg.Claro)
}
function Get-EstiloUsable {
    $e = if ($Estilos.Contains([string]$cfg.Estilo)) { [string]$cfg.Estilo } else { 'Solido' }
    if ($e -in $EstilosDiscord -and -not $cfg.Discord.Id) { 'Solido' } else { $e }
}
function Set-Estilo([string]$k) {
    if ($k -in $EstilosDiscord -and -not $cfg.Discord.Id) {
        Request-Discord 'usar los estilos de vidrio' ([scriptblock]::Create("Set-Estilo '$k'"))
        return
    }
    # entrar o salir de Cristal cambia el tipo de ventana: hay que reabrir
    if (($k -eq 'Cristal') -ne [bool]$win.AllowsTransparency) {
        $txt = if ($k -eq 'Cristal') { "El vidrio transparente no desenfoca: se ve todo lo que hay detrás de la ventana.`n`nPara cambiarlo el Optimizador se cierra y se abre solo (unos segundos). Mover la ventana puede sentirse un poco menos fluido que con los otros estilos." }
               else { 'Para salir del vidrio transparente el Optimizador se cierra y se abre solo (unos segundos).' }
        if (-not (Show-Dialogo 'Hay que reabrir' $txt 'Reabrir' 'Cancelar' 'pregunta')) { return }
        $cfg.Estilo = $k
        Start-Reabrir
        return
    }
    $cfg.Estilo = $k
    Set-Tema $cfg.Tema ([bool]$cfg.Claro)
}

function Show-MenuTemas {
    $tilde = {
        param($sel)
        if (-not $sel) { return $null }
        $ok = New-Object Windows.Controls.TextBlock
        $ok.Text = [char]0xE73E; $ok.FontFamily = 'Segoe MDL2 Assets'; $ok.FontSize = 12; $ok.Foreground = $Colores.accent
        $ok.VerticalAlignment = 'Center'
        $ok
    }
    $e = @(@{ T = 'head'; Texto = 'ESTILO' })
    $actual = Get-EstiloUsable
    foreach ($k in $Estilos.Keys) {
        $der = & $tilde ($k -eq $actual)
        if ($k -in $EstilosDiscord -and -not $cfg.Discord.Id) {
            $der = New-Object Windows.Controls.TextBlock; $der.Text = [char]0xE72E; $der.FontFamily = 'Segoe MDL2 Assets'; $der.FontSize = 13
            $der.Foreground = $Colores.muted; $der.VerticalAlignment = 'Center'
        }
        $e += @{ T = 'item'; Texto = $Estilos[$k]; Der = $der; A = [scriptblock]::Create("Set-Estilo '$k'") }
    }
    $e += @{ T = 'sep' }
    $e += @{ T = 'head'; Texto = 'TAMAÑO' }
    $tam = if ($Tamanos.Contains([string]$cfg.Tamano)) { [string]$cfg.Tamano } else { 'Completo' }
    foreach ($k in $Tamanos.Keys) {
        $e += @{ T = 'item'; Texto = $Tamanos[$k]; Der = (& $tilde ($k -eq $tam)); A = [scriptblock]::Create("Set-Tamano '$k'") }
    }
    $e += @{ T = 'sep' }
    $e += @{ T = 'head'; Texto = 'COLOR' }
    foreach ($k in $Temas.Keys) {
        $t = $Temas[$k]
        # muestra: circulito con el degradé del tema, y un tilde si es el actual
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        if ($k -eq $cfg.Tema -and -not ($k -in $TemasDiscord -and -not $cfg.Discord.Id)) {
            $ok = New-Object Windows.Controls.TextBlock
            $ok.Text = [char]0xE73E; $ok.FontFamily = 'Segoe MDL2 Assets'; $ok.FontSize = 12; $ok.Foreground = $Colores.accent
            $ok.VerticalAlignment = 'Center'; $ok.Margin = New-Object Windows.Thickness 0, 0, 10, 0
            [void]$sp.Children.Add($ok)
        }
        if ($k -in $TemasDiscord -and -not $cfg.Discord.Id) {
            $lk = New-Object Windows.Controls.TextBlock; $lk.Text = [char]0xE72E; $lk.FontFamily = 'Segoe MDL2 Assets'; $lk.FontSize = 13
            $lk.Foreground = $Colores.muted; $lk.VerticalAlignment = 'Center'; $lk.Width = 16; $lk.TextAlignment = 'Center'
            [void]$sp.Children.Add($lk)
        } else {
            $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 16; $dot.Height = 16
            $dot.Fill = (New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($t.A)), ([Windows.Media.ColorConverter]::ConvertFromString($t.B)), 45).psobject.BaseObject
            [void]$sp.Children.Add($dot)
        }
        $e += @{ T = 'item'; Texto = $t.Nombre; Der = $sp; A = [scriptblock]::Create("Set-TemaPedido '$k'") }
    }
    # personalizado: candado sin sesión de Discord; con sesión, el color elegido (o un arcoíris si todavía no eligió)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    if ($cfg.Tema -eq 'Personal' -and (Test-Personal)) { $ok = & $tilde $true; $ok.Margin = New-Object Windows.Thickness 0, 0, 10, 0; [void]$sp.Children.Add($ok) }
    if (-not $cfg.Discord.Id) {
        $lk = New-Object Windows.Controls.TextBlock; $lk.Text = [char]0xE72E; $lk.FontFamily = 'Segoe MDL2 Assets'; $lk.FontSize = 13
        $lk.Foreground = $Colores.muted; $lk.VerticalAlignment = 'Center'; $lk.Width = 16; $lk.TextAlignment = 'Center'
        [void]$sp.Children.Add($lk)
    } else {
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 16; $dot.Height = 16
        if (Test-Personal) { $tp = Get-TemaPersonal; $dot.Fill = New-Degrade $tp.A $tp.B; $dot.Fill.StartPoint = '0,0'; $dot.Fill.EndPoint = '1,1' }
        else { $dot.Fill = New-Degrade '#F43F5E' '#3B82F6' }
        [void]$sp.Children.Add($dot)
    }
    $e += @{ T = 'item'; Texto = 'Personalizado…'; Der = $sp; A = { Use-ColorPersonal } }
    $e += @{ T = 'sep' }
    # Neón es siempre oscuro
    if ($actual -ne 'Neon') { $e += @{ T = 'toggle'; Texto = 'Modo claro'; On = [bool]$cfg.Claro; A = { Set-Tema $cfg.Tema (-not $cfg.Claro) } } }
    if ($cfg.Discord.Id) { $e += @{ T = 'item'; Texto = "Cerrar sesión de Discord ($($cfg.Discord.Nombre))"; A = { Exit-Discord } } }
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
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-7) })
    $n = $ev.Count
    $dias = if ($n) { [math]::Floor(((Get-Date) - $ev[0].TimeCreated).TotalDays) } else { 0 }
    $ui.StatBsodSub.Text = 'Últimos 7 días'
    if ($n -eq 0) { $ui.StatBsod.Text = 'Estable'; $ui.StatBsod.Foreground = $Colores.ok }
    elseif ($dias -ge 3) {
        # tuvo pantallazos pero hace días que no: probablemente ya lo arreglaron (la RAM, un driver)
        $ui.StatBsod.Text = "$n BSOD"; $ui.StatBsod.Foreground = $Colores.warn
        $ui.StatBsodSub.Text = "0 en $dias días"
    }
    else { $ui.StatBsod.Text = "$n BSOD"; $ui.StatBsod.Foreground = $Colores.err }
    $up = (Get-Date) - $os.LastBootUpTime
    $ui.StatUp.Text = if ($up.TotalDays -ge 1) { '{0:N0} d' -f [math]::Floor($up.TotalDays) }
                      elseif ($up.TotalHours -ge 1) { '{0:N0} h' -f [math]::Floor($up.TotalHours) }
                      else { '{0:N0} min' -f [math]::Floor($up.TotalMinutes) }
    $ui.StatUpSub.Text = 'Sin reiniciar'
    $ui.StatUp.Foreground = if ($up.TotalDays -gt 7) { $Colores.warn } else { $Colores.text }
}

# ---------- tarjeta de disco: con varios discos, clic pasa al siguiente ----------
# solo discos fijos (sin pendrives ni lectoras); el elegido queda guardado en la config
# Win32_LogicalDisk (instantáneo) con los mismos nombres que tenía Get-Volume, que tardaba ~10 s en cargar
function Get-Discos {
    @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object Size | Sort-Object DeviceID | ForEach-Object {
        [pscustomobject]@{ DriveLetter = $_.DeviceID[0]; FileSystemLabel = $_.VolumeName; SizeRemaining = [double]$_.FreeSpace; Size = [double]$_.Size }
    })
}
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
    # redondeado para abajo, como el Explorador de Windows (147,6 GB libres = 147, no 148)
    $ui.StatDisk.Text = '{0} GB' -f [math]::Floor($d.SizeRemaining / 1GB)
    $ui.StatDiskSub.Text = 'Libres de {0} GB' -f [math]::Floor($d.Size / 1GB)
    # menos de 10% libre: en amarillo, como el resto de las alertas
    $ui.StatDisk.Foreground = if ($d.SizeRemaining / $d.Size -lt 0.1) { $Colores.warn } else { $Colores.text }
    Set-BarraDisco $ui.DiskBar (1 - $d.SizeRemaining / $d.Size)
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
        # como "Este equipo": ícono, nombre, barra de lo ocupado y "X GB disponibles de Y GB"
        $g = New-Object Windows.Controls.Grid
        foreach ($ancho in 'Auto', '230', 'Auto') { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $ancho; [void]$g.ColumnDefinitions.Add($c) }
        $ico = New-Object Windows.Controls.TextBlock
        $ico.Text = [char]0xEDA2; $ico.FontFamily = 'Segoe MDL2 Assets'; $ico.FontSize = 22; $ico.Foreground = $Colores.muted
        $ico.VerticalAlignment = 'Center'; $ico.Margin = New-Object Windows.Thickness 0, 0, 12, 0
        [void]$g.Children.Add($ico)
        $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
        $nombre = if ($d.FileSystemLabel) { $d.FileSystemLabel } else { 'Disco local' }
        $tn = New-Object Windows.Controls.TextBlock
        $tn.Text = "$nombre ($($d.DriveLetter):)"; $tn.FontSize = 13; $tn.Foreground = $Colores.text
        [void]$sp.Children.Add($tn)
        $barra = New-Object Windows.Controls.Grid; $barra.Height = 6; $barra.Margin = New-Object Windows.Thickness 0, 4, 0, 3
        Set-BarraDisco $barra (1 - $d.SizeRemaining / $d.Size)
        [void]$sp.Children.Add($barra)
        $tl = New-Object Windows.Controls.TextBlock
        $tl.Text = '{0:N0} GB disponibles de {1:N0} GB' -f [math]::Floor($d.SizeRemaining / 1GB), [math]::Floor($d.Size / 1GB); $tl.FontSize = 11; $tl.Foreground = $Colores.muted
        [void]$sp.Children.Add($tl)
        [void]$g.Children.Add($sp)
        if ($d.DriveLetter -eq $actual) {
            $ok = New-Object Windows.Controls.TextBlock
            $ok.Text = [char]0xE73E; $ok.FontFamily = 'Segoe MDL2 Assets'; $ok.FontSize = 12; $ok.Foreground = $Colores.accent
            $ok.VerticalAlignment = 'Center'; $ok.Margin = New-Object Windows.Thickness 12, 0, 0, 0
            [Windows.Controls.Grid]::SetColumn($ok, 2); [void]$g.Children.Add($ok)
        }
        $e += @{ T = 'item'; Texto = $g; A = [scriptblock]::Create("`$cfg.Disco = '$($d.DriveLetter)'; Save-Cfg; Show-Disco") }
    }
    Show-Menu $e
}

# barra de lo ocupado, con los colores de Windows: azul, amarillo desde el 75% y rojo desde el 90%
# (dos columnas proporcionales: no depende de saber el ancho en píxeles)
$AzulDisco = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x3D, 0x8B, 0xFD))
function Set-BarraDisco($grid, [double]$usado) {
    # 0.0 y 1.0, no 0 y 1: con un entero primero [math]::Max elige la versión entera y 0.83 se vuelve 1
    $usado = [math]::Min(1.0, [math]::Max(0.0, $usado))
    $grid.Children.Clear(); $grid.ColumnDefinitions.Clear()
    foreach ($v in $usado, (1 - $usado)) {
        $c = New-Object Windows.Controls.ColumnDefinition
        $c.Width = New-Object Windows.GridLength ([math]::Max($v, 0.0001)), ([Windows.GridUnitType]::Star)
        [void]$grid.ColumnDefinitions.Add($c)
    }
    $radio = New-Object Windows.CornerRadius ($grid.Height / 2)
    $pista = New-Object Windows.Controls.Border; $pista.Background = $Colores.toggleOff; $pista.CornerRadius = $radio
    [Windows.Controls.Grid]::SetColumnSpan($pista, 2); [void]$grid.Children.Add($pista)
    $lleno = New-Object Windows.Controls.Border; $lleno.CornerRadius = $radio
    $lleno.Background = if ($usado -ge 0.9) { $Colores.err } elseif ($usado -ge 0.75) { $Colores.warn } else { $AzulDisco }
    [void]$grid.Children.Add($lleno)
}
$ui.DiskCard.Add_MouseLeftButtonUp({ Show-MenuDiscos })

# ---------- ejecutar acciones en segundo plano ----------
$sync = [hashtable]::Synchronized(@{ Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]' })
$script:Job = $null
$Botones = 'BtnTodo', 'BtnLimpieza', 'BtnJuego', 'BtnRed', 'BtnDiag', 'BtnReparar', 'BtnRestaurar', 'BtnRouter'

function Start-Accion($accion) {
    if ($script:Job) { return }
    $script:AccionActual = $accion
    Set-Tab 'act'   # lo que hace la acción se ve en Actividad
    foreach ($b in $Botones) { $ui[$b].IsEnabled = $false }
    if ($ui.Log.Document.Blocks.Count) { Add-Line '' }
    $ui.Prog.Value = 0; $ui.Pct.Text = '0%'; $ui.Status.Text = 'Arrancando...'
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('Raiz', $Raiz)
    $rs.SessionStateProxy.SetVariable('Simular', [bool]$Simular)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script_ = $FnInicio.ToString() + "`n" + $Core.ToString() + "`ntry { Invoke-Accion '$accion' } catch { Out-Line ('Error: ' + `$_.Exception.Message) 'err'; Log-Archivo ('Error en $accion' + ': ' + `$_.Exception.Message + ' | ' + ((`$_.ScriptStackTrace -split ""`n"") -join ' < ')) } finally { `$sync.Q.Enqueue(@{ Tipo = 'done' }) }"
    [void]$ps.AddScript($script_)
    $script:Job = @{ PS = $ps; RS = $rs; H = $ps.BeginInvoke() }
}

function End-Accion {
    if ($script:Job) { try { $script:Job.PS.EndInvoke($script:Job.H) } catch { }; $script:Job.PS.Dispose(); $script:Job.RS.Dispose() }
    $script:Job = $null
    foreach ($b in $Botones) { $ui[$b].IsEnabled = $true }
    if ($script:AccionActual -eq 'router') { $script:RouterReinicioHasta = (Get-Date).AddSeconds(30) }
    $ui.Prog.Value = 100; $ui.Pct.Text = '100%'; $ui.Status.Text = 'Listo'
    Update-Stats
    # la captura espera a que el overlay tenga datos (la saca el timer del overlay)
    if ($Captura) { $script:CapturaLista = Get-Date; return }
    # desinstalando: ya se restauraron los ajustes, sigue borrando lo instalado
    if ($script:DesinstalarDespues) { $script:DesinstalarDespues = $false; Finish-Desinstalar; return }
    # las del modo juego automático no suenan: pasan con el juego abierto
    if ($script:AccionActual -notin 'autojuego', 'finjuego') { Play-Listo }
    # asistente de la primera vez: terminó la revisión, muestra el puntaje y ofrece arreglar
    if ($script:AsistenteEnCurso -and $script:AccionActual -eq 'diagnostico') { Show-ResumenAsistente }
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
    # y un menú: el de elegir datos, o el de discos con -Vista discos (captura_menu.png)
    if ($Vista -eq 'discos') { Show-MenuDiscos } elseif ($Vista -eq 'apariencia') { Show-MenuTemas } else { Show-MenuDatos }
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
$script:TimerRapido = [TimeSpan]::FromMilliseconds(80); $script:TimerLento = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    # en la bandeja y sin nada corriendo no hace falta mirar la cola 12 veces por segundo
    $quiere = if ($win.IsVisible -or $script:Job -or $script:UpdEsperaHasta -or $script:UpdEnCurso) { $script:TimerRapido } else { $script:TimerLento }
    if ($timer.Interval -ne $quiere) { $timer.Interval = $quiere }
    $m = $null
    while ($sync.Q.TryDequeue([ref]$m)) {
        switch ($m.Tipo) {
            'line' { Add-Line $m.T $m.K }
            'prog' { $ui.Prog.Value = $m.P; $ui.Pct.Text = "$($m.P)%"; $ui.Status.Text = $m.L }
            'done' { End-Accion }
            'update' { Handle-Update $m }
            'updprog' { Handle-UpdProgreso $m }
            'mipc' { Handle-MiPc $m }
            'puntaje' { Handle-Puntaje $m }
            'upddl' { Finish-Update $m }
            'espmed' { Handle-EspMed $m }
            'esplimp' { Handle-EspProg $m }
            'espfin' { Handle-EspFin $m }
            'espanal' { Handle-EspAnal $m }
        }
    }
    # actualizando: cuando la versión nueva avisa que abrió se cierra esta; si a los 30 s no avisó, esta sigue
    if ($script:UpdEsperaHasta) {
        if ($script:EvtListo.WaitOne(0)) { $script:UpdEsperaHasta = $null; Close-UpdDialogo; Salir }
        elseif ((Get-Date) -ge $script:UpdEsperaHasta) {
            $script:UpdEsperaHasta = $null
            if ($script:Reabriendo) {
                $script:Reabriendo = $false; $script:Actualizando = $false
                try { $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps') } catch { }
                Show-Dialogo 'No se reabrió' 'El estilo quedó guardado: se aplica la próxima vez que abras el Optimizador (paloma de la bandeja > Salir y abrirlo de nuevo).' 'Entendido' '' 'alerta' | Out-Null
            } else { Update-NoAbrio }
        }
    }
})
$timer.Start()

# ---------- eventos ----------
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnClose.Add_Click({ Hide-Main })
$ui.BtnOverlay.Add_Click({ Set-Overlay (-not $ov.IsVisible) })
$ui.BtnTema.Add_Click({ Show-MenuTemas })
$ui.PerfilChip.Add_Click({ Show-MenuPerfil })
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

ROUTER
Si tu router es un Movistar Fibra aparece la fila "Router" con el estado de internet y el botón Reiniciar: entra al router, lo reinicia y te avisa cuando vuelve internet (unos 2 minutos). La primera vez pide la contraseña de la etiqueta de abajo del router y la guarda cifrada en tu PC. Con cualquier router, si deja de contestar más de 25 segundos te avisa con un globo, y cuenta cuántas veces se cortó en el día.

RESTAURAR AJUSTES
Deja la red, el plan de energía y la Game Bar exactamente como estaban antes (se guarda un respaldo la primera vez).

REVISIÓN COMPLETA
Revisa la RAM (y si va más lenta de lo que da: XMP/EXPO), los pantallazos azules de la última semana explicados con qué probar primero, el espacio y la salud de los discos, los programas de arranque, el driver de video, el cable de red, la energía y la Game Bar. Da un puntaje de 0 a 100 y la lista de qué mejorar, de lo más importante a lo menos, marcando lo que se arregla solo con Todo para jugar. No cambia nada.

MI PC (a la derecha)
Las especificaciones: procesador, placa de video, RAM, placa madre, discos, monitor, Windows y red. "Copiar para Discord" arma un resumen para pegar.

REPARAR WINDOWS
DISM + SFC: revisa los archivos de Windows y arregla los dañados. Tarda 10 a 30 minutos.

PUNTO DE RESTAURACIÓN
Antes de Red y de Reparar Windows se crea un punto de restauración de Windows (si Windows ya hizo uno hoy, usa ese).

QUÉ NO HACE
No borra fotos, documentos, descargas ni la Papelera. No toca servicios ni el BIOS, y en el registro solo cambia los ajustes de Red (con respaldo). No cambia tu DNS ni tu IP. No manda datos a ningún lado (solo hace un ping a 1.1.1.1 para medir tu latencia en pantalla y una vez por día se fija en GitHub si hay versión nueva).

DATOS EN PANTALLA
Ctrl+Shift+O los muestra u oculta desde cualquier lado, incluso jugando. También el botón del monitor (arriba) o click derecho en la paloma de la bandeja. Se pueden arrastrar, y con click derecho elegís la esquina. Se ven en juegos en ventana o pantalla completa sin bordes.

INICIAR CON WINDOWS
Abajo (o en el menú de la paloma). Prendido, al prender la PC el Optimizador se abre solo, sin aviso de permisos, así el modo juego automático y los datos en pantalla ya están listos. Viene apagado. Necesita que esté instalado.

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
  <Border x:Name="Box" CornerRadius="12" Background="{DynamicResource OvBg}" BorderBrush="{DynamicResource OvLine}" BorderThickness="1" Padding="10,7,0,7" Cursor="SizeAll">
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
    gpu  = @('Uso de GPU',        'GrpGpu',  'gpu')
    temp = @('Temperatura de GPU', 'GrpTemp', 'temp')   # solo NVIDIA: Windows no da la temperatura de otras placas
    vram = @('VRAM',              'GrpVram', 'gpu')
    ping = @('Ping',              'GrpPing', $false)
    hora = @('Hora',              'OvHora',  $false)
}
function Apply-Datos {
    foreach ($k in $Datos.Keys) {
        $d = $Datos[$k]
        $hay = switch ($d[2]) { 'gpu' { $stats.HayGpu -ne $false } 'temp' { $stats.HayTemp -ne $false } default { $true } }
        $ver = ($cfg.Datos -contains $k) -and $hay
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
        if ($Datos[$k][2] -eq 'temp' -and $stats.HayTemp -eq $false) { $nombre += '  (solo NVIDIA)' }
        elseif ($Datos[$k][2] -eq 'gpu' -and $stats.HayGpu -eq $false) { $nombre += '  (no disponible)' }
        $e += @{ T = 'check'; Texto = $nombre; Clave = $k }
    }
    Show-Menu $e
}
if ($logo) { $b = New-Object Windows.Media.ImageBrush $logo; $b.Stretch = 'UniformToFill'; $ovUi.OvLogo.Fill = $b }

# ---------- configuración guardada (visible, esquina, posición a mano) ----------
$cfgPath = Join-Path $Raiz 'config.json'
$cfg = @{ Overlay = $false; Pos = 'TR'; Left = 0; Top = 0; Tema = 'Esmeralda'; Claro = $false; Estilo = 'Solido'; Tamano = 'Completo'; Discord = $null; ColorPersonal = ''
          Datos = @('logo', 'cpu', 'ram', 'gpu', 'temp', 'vram', 'ping', 'hora')
          # modo juego automático: N = nombre que se muestra, P = nombre del proceso (acepta *)
          # FiveM: el que importa es el proceso del juego (FiveM_b3258_GTAProcess), no el launcher
          AutoJuego = $false; Juegos = @(@{ N = 'FiveM'; P = 'FiveM_*GTAProcess' }, @{ N = 'GTA V'; P = 'GTA5' }) }
if (Test-Path $cfgPath) {
    $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
    foreach ($k in 'Overlay', 'Pos', 'Left', 'Top', 'Tema', 'Claro', 'Estilo', 'Tamano', 'Discord', 'ColorPersonal', 'Datos', 'NoInstalar', 'Disco', 'AutoJuego', 'Juegos', 'UltPuntaje', 'UltEtiqueta', 'AsistenteVisto') { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } }
}
function Save-Cfg {
    if ($Captura) { return }   # las capturas de prueba no tocan tu configuración
    if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
    $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
}

# área de trabajo (sin la barra de tareas) de un monitor, en unidades de WPF.
# SystemParameters.WorkArea es siempre el monitor principal: con dos monitores dejaba todo en el principal.
function Get-AreaMonitor([Windows.Forms.Screen]$pantalla) {
    $r = $pantalla.WorkingArea
    $src = [Windows.PresentationSource]::FromVisual($win)
    if (-not $src) { return [Windows.SystemParameters]::WorkArea }
    $t = $src.CompositionTarget.TransformFromDevice   # píxeles reales → unidades de WPF (zoom de Windows)
    New-Object Windows.Rect ($t.Transform((New-Object Windows.Point $r.Left, $r.Top))), ($t.Transform((New-Object Windows.Point $r.Right, $r.Bottom)))
}

function Set-OvPos($pos) {
    $cfg.Pos = $pos
    # las esquinas son las del monitor donde está el overlay (si lo arrastraste al segundo, queda ahí)
    $wa = Get-AreaMonitor ([Windows.Forms.Screen]::FromHandle((New-Object Windows.Interop.WindowInteropHelper $ov).EnsureHandle()))
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
    // RAM con GlobalMemoryStatusEx: lo mismo que WMI pero sin consultar un servicio cada segundo
    [StructLayout(LayoutKind.Sequential)] struct MEMSTAT { public uint len, load; public ulong total, avail, tp, ap, tv, av, ae; }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMSTAT m);
    public static double[] Ram() {
        var m = new MEMSTAT(); m.len = (uint)Marshal.SizeOf(m); GlobalMemoryStatusEx(ref m);
        return new double[] { m.total - m.avail, m.total };
    }
}
// NVIDIA directo por NVML (la librería que usa nvidia-smi por dentro): se conecta una vez y cada lectura tarda ~1 ms.
// Abrir nvidia-smi cada segundo tardaba ~90 ms y conectaba/desconectaba el driver cada vez, lo que da microtirones.
public static class Nvml {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string ruta);
    [DllImport("nvml.dll")] static extern int nvmlInit_v2();
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetHandleByIndex_v2(uint i, out IntPtr d);
    [DllImport("nvml.dll", CharSet = CharSet.Ansi)] static extern int nvmlDeviceGetName(IntPtr d, System.Text.StringBuilder s, uint n);
    [StructLayout(LayoutKind.Sequential)] struct UTIL { public uint gpu, mem; }
    [StructLayout(LayoutKind.Sequential)] struct MEM { public ulong total, free, used; }
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetUtilizationRates(IntPtr d, out UTIL u);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetTemperature(IntPtr d, int sensor, out uint t);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetMemoryInfo(IntPtr d, out MEM m);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetPowerUsage(IntPtr d, out uint mw);
    [DllImport("nvml.dll")] static extern int nvmlDeviceGetClockInfo(IntPtr d, int tipo, out uint mhz);
    static IntPtr dev;
    public static string Nombre = "";
    public static bool Iniciar() {
        try {
            // drivers nuevos la ponen en System32; los viejos, en la carpeta NVSMI
            if (LoadLibrary("nvml.dll") == IntPtr.Zero &&
                LoadLibrary(Environment.ExpandEnvironmentVariables(@"%ProgramFiles%\NVIDIA Corporation\NVSMI\nvml.dll")) == IntPtr.Zero) return false;
            if (nvmlInit_v2() != 0 || nvmlDeviceGetHandleByIndex_v2(0, out dev) != 0) return false;
            var sb = new System.Text.StringBuilder(96); if (nvmlDeviceGetName(dev, sb, 96) == 0) Nombre = sb.ToString();
            return true;
        } catch { return false; }
    }
    // uso %, temperatura, VRAM usada y total (MB), consumo (W, -1 si la placa no lo informa), frecuencia (MHz)
    public static double[] Leer() {
        UTIL u; uint t, mw, mhz; MEM m;
        if (nvmlDeviceGetUtilizationRates(dev, out u) != 0) return null;
        nvmlDeviceGetTemperature(dev, 0, out t);
        nvmlDeviceGetMemoryInfo(dev, out m);
        double w = nvmlDeviceGetPowerUsage(dev, out mw) == 0 ? mw / 1000.0 : -1;
        nvmlDeviceGetClockInfo(dev, 0, out mhz);
        return new double[] { u.gpu, t, m.used / 1048576.0, m.total / 1048576.0, w, mhz };
    }
}
'@
    $nvml = [Nvml]::Iniciar()
    # nvidia-smi solo si NVML no está (no debería pasar con un driver de NVIDIA instalado)
    $smi = if ($nvml) { $null } else { (Get-Command nvidia-smi).Source }
    # sin NVIDIA (AMD, Intel): uso y VRAM salen de los contadores de Windows, que andan con cualquier placa.
    # La temperatura no: Windows no la expone, cada marca usa su propio programa.
    $gpuCat = $null; $gpuCont = @{}; $gpuLista = [datetime]::MinValue; $vramTot = 0
    if (-not $nvml -and -not $smi) {
        try { $gpuCat = New-Object Diagnostics.PerformanceCounterCategory 'GPU Engine'; [void]$gpuCat.GetInstanceNames() } catch { $gpuCat = $null }
        # VRAM total: del registro (Win32_VideoController la corta en 4 GB)
        Get-ChildItem 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' | ForEach-Object {
            $q = (Get-ItemProperty $_.PSPath).'HardwareInformation.qwMemorySize'
            if ($q -and [double]$q -gt $vramTot) { $vramTot = [double]$q }
        }
    }
    $stats.HayGpu = $nvml -or [bool]$smi -or [bool]$gpuCat
    $stats.HayTemp = $nvml -or [bool]$smi
    # datos fijos para la pestaña Rendimiento
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $stats.CpuNombre = ($cpu.Name -replace '\s+', ' ').Trim(); $stats.CpuNucleos = $cpu.NumberOfCores; $stats.CpuHilos = $cpu.NumberOfLogicalProcessors
    if ($nvml) { $stats.GpuNombre = [Nvml]::Nombre }
    elseif ($smi) { $stats.GpuNombre = ([JVps.Consola]::Correr($smi, '--query-gpu=name --format=csv,noheader', 10000) | Select-Object -First 1) }
    else { $stats.GpuNombre = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' } | Select-Object -First 1).Name }
    $ping = New-Object Net.NetworkInformation.Ping
    [void][CpuMeter]::Sample()
    $nucleos = [Environment]::ProcessorCount
    $previo = @{}; $tPrevio = Get-Date
    $n = 0
    while ($stats.Run) {
        Start-Sleep -Milliseconds 1000
        # mide solo si se ve algo: el overlay o la pestaña Rendimiento
        if (-not $stats.Visible -and -not $stats.Panel) { continue }
        $stats.Cpu = [math]::Round([CpuMeter]::Sample())
        $mem = [CpuMeter]::Ram()
        $stats.RamUsada = $mem[0] / 1GB; $stats.RamTotal = $mem[1] / 1GB
        if ($gpuCat -and $n % 2 -eq 0) {
            # los motores 3D de cada proceso: la lista cambia cuando se abren o cierran programas
            if (((Get-Date) - $gpuLista).TotalSeconds -ge 10) {
                $gpuLista = Get-Date
                $inst = @($gpuCat.GetInstanceNames() | Where-Object { $_ -like '*engtype_3D' })
                foreach ($k in @($gpuCont.Keys)) { if ($inst -notcontains $k) { $gpuCont[$k].Dispose(); $gpuCont.Remove($k) } }
                foreach ($i in $inst) { if (-not $gpuCont.ContainsKey($i)) { try { $c = New-Object Diagnostics.PerformanceCounter 'GPU Engine', 'Utilization Percentage', $i, $true; [void]$c.NextValue(); $gpuCont[$i] = $c } catch { } } }
            }
            $s = 0.0; foreach ($c in $gpuCont.Values) { try { $s += $c.NextValue() } catch { } }
            $stats.Gpu = [int][math]::Min(100, [math]::Round($s))
            $usada = 0.0
            try { $m = New-Object Diagnostics.PerformanceCounterCategory 'GPU Adapter Memory'; foreach ($i in $m.GetInstanceNames()) { $c = New-Object Diagnostics.PerformanceCounter 'GPU Adapter Memory', 'Dedicated Usage', $i, $true; $usada += $c.NextValue(); $c.Dispose() } } catch { }
            $stats.Vram = $usada / 1GB; $stats.VramTotal = $vramTot / 1GB
        }
        if ($nvml) {
            $g = [Nvml]::Leer()
            if ($g) {
                $stats.Gpu = [int]$g[0]; $stats.GpuTemp = [int]$g[1]
                $stats.Vram = $g[2] / 1024; $stats.VramTotal = $g[3] / 1024
                $stats.GpuW = if ($g[4] -ge 0) { $g[4] } else { $null }; $stats.GpuMhz = [int]$g[5]
            }
        }
        elseif ($smi) {
            $o = [JVps.Consola]::Correr($smi, '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,clocks.gr --format=csv,noheader,nounits', 5000) | Select-Object -First 1
            if ($o) {
                $p = $o -split ',\s*'
                $stats.Gpu = [int]$p[0]; $stats.GpuTemp = [int]$p[1]
                $stats.Vram = [double]$p[2] / 1024; $stats.VramTotal = [double]$p[3] / 1024
                $stats.GpuW = $p[4] -as [double]; $stats.GpuMhz = $p[5] -as [int]   # algunas placas no informan consumo: queda vacío
            }
        }
        # qué programas usan la CPU (cada 2 s, solo con la pestaña a la vista): tiempo de CPU de cada proceso
        # entre una medición y la otra, sumado por nombre (todos los chrome cuentan como uno)
        if ($stats.Panel -and $n % 2 -eq 0) {
            $ahora = Get-Date; $ms = ($ahora - $tPrevio).TotalMilliseconds; $tPrevio = $ahora
            $actual = @{}; $uso = @{}; $ram = @{}
            foreach ($pr in Get-Process) {
                if ($pr.Id -eq 0) { continue }   # "Idle" es el tiempo libre, no un programa
                $t = $pr.TotalProcessorTime.TotalMilliseconds
                $ram[$pr.ProcessName] += $pr.WorkingSet64
                if ($null -eq $pr.TotalProcessorTime) { continue }
                $actual[$pr.Id] = $t
                if ($previo.ContainsKey($pr.Id)) { $uso[$pr.ProcessName] += ($t - $previo[$pr.Id]) }
            }
            $previo = $actual
            if ($ms -gt 0 -and $uso.Count) {
                $stats.Top = @($uso.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
                    @{ N = $_.Key; Cpu = [math]::Round($_.Value * 100 / ($ms * $nucleos), 1); Ram = $ram[$_.Key] }
                })
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
        if ($stats.HayTemp) { $ovUi.OvTemp.Text = "$($stats.GpuTemp)°C"; $ovUi.OvTemp.Foreground = Color-Por $stats.GpuTemp 75 83 }
        $ovUi.OvVram.Text = '{0:N1}/{1:N0} GB' -f $stats.Vram, $stats.VramTotal
        $ovUi.OvVram.Foreground = Color-Por ($stats.Vram * 100 / [math]::Max(1.0, $stats.VramTotal)) 85 95
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

# ---------- pestaña Rendimiento: CPU, GPU y RAM en vivo con gráfico del último minuto ----------
$Hist = @{ Cpu = New-Object 'Collections.Generic.List[double]'; Gpu = New-Object 'Collections.Generic.List[double]'; Ram = New-Object 'Collections.Generic.List[double]' }

# pestañas del panel derecho: 'act' (Actividad), 'rend' (Rendimiento) o 'pc' (Mi PC)
$script:Pestana = 'act'
function Set-Tab([string]$cual) {
    $script:Pestana = $cual
    $ui.ActPanel.Visibility = if ($cual -eq 'act') { 'Visible' } else { 'Collapsed' }
    $ui.RendPanel.Visibility = if ($cual -eq 'rend') { 'Visible' } else { 'Collapsed' }
    $ui.PcPanel.Visibility = if ($cual -eq 'pc') { 'Visible' } else { 'Collapsed' }
    $ui.IniPanel.Visibility = if ($cual -eq 'ini') { 'Visible' } else { 'Collapsed' }
    $ui.EspPanel.Visibility = if ($cual -eq 'esp') { 'Visible' } else { 'Collapsed' }
    $ui.Pct.Visibility = if ($cual -eq 'act') { 'Visible' } else { 'Collapsed' }
    foreach ($t in @(@($ui.TabAct, 'act'), @($ui.TabRend, 'rend'), @($ui.TabPc, 'pc'), @($ui.TabIni, 'ini'), @($ui.TabEsp, 'esp'))) {
        $t[0].Foreground = if ($t[1] -eq $cual) { $Colores.text } else { $Colores.muted }
        $t[0].FontWeight = if ($t[1] -eq $cual) { 'SemiBold' } else { 'Normal' }
    }
    if ($cual -eq 'rend') { $ui.RendPanel.ScrollToTop(); $script:UltTick = $null; Update-Rendimiento }
    if ($cual -eq 'pc' -and -not $script:MiPc) { Start-MiPc }   # se junta una sola vez (tarda un segundo)
    if ($cual -eq 'ini') { Show-Inicio -Releer }   # se vuelve a leer cada vez: pudieron cambiarlo desde el Administrador de tareas
    if ($cual -eq 'esp') { Show-Espacio }
}

function Add-Hist($clave, [double]$valor) {
    $l = $Hist[$clave]; $l.Add([math]::Min(100.0, [math]::Max(0.0, $valor)))   # .0: si no, redondea a entero
    while ($l.Count -gt 60) { $l.RemoveAt(0) }
}

# línea + relleno; el último dato queda pegado a la derecha y el gráfico va entrando a medida que junta datos
function Draw-Graf($lienzo, $linea, $relleno, $datos) {
    $w = $lienzo.ActualWidth; $h = $lienzo.ActualHeight
    if ($w -le 0 -or $datos.Count -lt 2) { $linea.Points = $null; $relleno.Points = $null; return }
    $paso = $w / 59; $x0 = $w - ($datos.Count - 1) * $paso
    $pl = New-Object Windows.Media.PointCollection; $pf = New-Object Windows.Media.PointCollection
    $pf.Add((New-Object Windows.Point $x0, $h))
    for ($i = 0; $i -lt $datos.Count; $i++) {
        $pt = New-Object Windows.Point ($x0 + $i * $paso), ($h - 1 - $datos[$i] * ($h - 2) / 100)
        $pl.Add($pt); $pf.Add($pt)
    }
    $pf.Add((New-Object Windows.Point $w, $h))
    $linea.Points = $pl; $relleno.Points = $pf
}

function Update-Rendimiento {
    if (-not $stats.Tick -or $stats.Tick -eq $script:UltTick) { return }
    $script:UltTick = $stats.Tick
    $pctRam = $stats.RamUsada * 100 / [math]::Max(1.0, $stats.RamTotal)
    Add-Hist Cpu $stats.Cpu; Add-Hist Ram $pctRam
    if ($stats.HayGpu) { Add-Hist Gpu $stats.Gpu }
    if ($ui.RendPanel.Visibility -ne 'Visible') { return }

    $ui.RCpuNom.Text = $stats.CpuNombre
    $ui.RCpuVal.Text = "$($stats.Cpu)%"; $ui.RCpuVal.Foreground = Color-Por $stats.Cpu 70 90
    $ui.RCpuSub.Text = "$($stats.CpuNucleos) núcleos · $($stats.CpuHilos) hilos"
    Draw-Graf $ui.GrCpu $ui.GrCpuLine $ui.GrCpuFill $Hist.Cpu

    $ui.RGpuNom.Text = if ($stats.GpuNombre) { $stats.GpuNombre } else { 'Placa de video' }
    if ($stats.HayGpu) {
        $ui.RGpuVal.Text = "$($stats.Gpu)%"; $ui.RGpuVal.Foreground = Color-Por $stats.Gpu 85 98
        $d = @()
        if ($stats.HayTemp) { $d += "$($stats.GpuTemp)°C" }
        $d += if ($stats.VramTotal) { 'VRAM {0:N1} de {1:N0} GB' -f $stats.Vram, $stats.VramTotal } else { 'VRAM {0:N1} GB' -f $stats.Vram }
        if ($stats.GpuW) { $d += '{0:N0} W' -f $stats.GpuW }
        if ($stats.GpuMhz) { $d += "$($stats.GpuMhz) MHz" }
        $ui.RGpuSub.Text = $d -join ' · '
        $ui.RGpuSub.Foreground = if ($stats.GpuTemp -ge 83) { $Colores.err } elseif ($stats.GpuTemp -ge 75) { $Colores.warn } else { $Colores.muted }
    } else {
        $ui.RGpuVal.Text = '-'
        $ui.RGpuSub.Text = 'Windows no informa el uso de esta placa de video.'
    }
    Draw-Graf $ui.GrGpu $ui.GrGpuLine $ui.GrGpuFill $Hist.Gpu

    $ui.RRamNom.Text = '{0:N0} GB en total' -f $stats.RamTotal
    $ui.RRamVal.Text = '{0:N1} GB' -f $stats.RamUsada; $ui.RRamVal.Foreground = Color-Por $pctRam 75 90
    $ui.RRamSub.Text = '{0:N0}% en uso · {1:N1} GB libres' -f $pctRam, ($stats.RamTotal - $stats.RamUsada)
    Draw-Graf $ui.GrRam $ui.GrRamLine $ui.GrRamFill $Hist.Ram

    # los 5 programas que más CPU usan: nombre, % y RAM
    $ui.RTop.Children.Clear()
    if (-not $stats.Top) {
        $tb = New-Object Windows.Controls.TextBlock -Property @{ Text = 'Midiendo...'; FontSize = 11.5; Foreground = $Colores.muted }
        [void]$ui.RTop.Children.Add($tb)
    }
    foreach ($p in @($stats.Top)) {
        $g = New-Object Windows.Controls.Grid; $g.Margin = New-Object Windows.Thickness 0, 2, 0, 2
        foreach ($ancho in '*', '70', '52') { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $ancho; [void]$g.ColumnDefinitions.Add($c) }
        $celdas = @(
            @($p.N, $Colores.text, 'Left'),
            @(('{0:N0} MB' -f ($p.Ram / 1MB)), $Colores.muted, 'Right'),
            @(('{0:N1}%' -f $p.Cpu), (Color-Por $p.Cpu 25 50), 'Right')
        )
        for ($i = 0; $i -lt 3; $i++) {
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = $celdas[$i][0]; $tb.Foreground = $celdas[$i][1]; $tb.HorizontalAlignment = $celdas[$i][2]
            $tb.FontSize = 11.5; $tb.TextTrimming = 'CharacterEllipsis'
            [Windows.Controls.Grid]::SetColumn($tb, $i); [void]$g.Children.Add($tb)
        }
        [void]$ui.RTop.Children.Add($g)
    }
}

$ui.TabAct.Add_MouseLeftButtonUp({ Set-Tab 'act' })
$ui.TabRend.Add_MouseLeftButtonUp({ Set-Tab 'rend' })
$ui.TabPc.Add_MouseLeftButtonUp({ Set-Tab 'pc' })
$ui.TabIni.Add_MouseLeftButtonUp({ Set-Tab 'ini' })
$ui.TabEsp.Add_MouseLeftButtonUp({ Set-Tab 'esp' })

# ---------- pestaña Arranque: programas que arrancan con Windows ----------
$script:IconosInicio = @{}
function Get-IconoInicio($p) {
    $ruta = if ($p.Logo) { $p.Logo } else { $p.Exe }   # apps de la Tienda: su logo PNG; el resto: el ícono del .exe
    if (-not $ruta) { return $null }
    if (-not $script:IconosInicio.ContainsKey($ruta)) {
        $img = $null
        try {
            if ($p.Logo) {
                $img = New-Object Windows.Media.Imaging.BitmapImage
                $img.BeginInit(); $img.UriSource = New-Object Uri $ruta; $img.DecodePixelWidth = 40; $img.CacheOption = 'OnLoad'; $img.EndInit()
            } else {
                Add-Type -AssemblyName System.Drawing
                $ic = [Drawing.Icon]::ExtractAssociatedIcon($ruta)
                $img = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ic.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                $ic.Dispose()
            }
        } catch { }
        $script:IconosInicio[$ruta] = $img
    }
    $script:IconosInicio[$ruta]
}

# -Releer vuelve a leer el registro (al abrir la pestaña); el switch solo repinta la lista que ya está
function Show-Inicio([string]$aviso = '', [switch]$Releer) {
    if ($Releer -or -not $script:ListaInicio) { $script:ListaInicio = @(Get-ProgramasInicio -Detalles) }
    $lista = @($script:ListaInicio | Sort-Object @{ e = { -not $_.Activo } }, @{ e = { @{ apagar = 0; '' = 1; dejar = 2 }[$_.Tipo] } }, Nombre)
    $activos = @($lista | Where-Object Activo).Count
    $sobran = @($lista | Where-Object { $_.Activo -and $_.Tipo -eq 'apagar' }).Count
    $ui.IniResumen.Text = if (-not $lista) { 'No hay programas que arranquen con Windows.' }
        else { "$activos de $($lista.Count) se abren solos al prender la PC" + $(if ($sobran) { " · $sobran no hacen falta" }) }
    $ui.IniEstado.Text = if ($aviso) { $aviso } else { 'Apagarlos no los desinstala: los abrís cuando quieras y se vuelven a prender acá.' }

    $ui.IniLista.Children.Clear()
    foreach ($p in $lista) {
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = New-Object Windows.CornerRadius 10; $b.Padding = New-Object Windows.Thickness 10, 7, 12, 7
        $b.Margin = New-Object Windows.Thickness 0, 0, 0, 6
        $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
        $g = New-Object Windows.Controls.Grid
        foreach ($ancho in '30', '*', 'Auto') { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $ancho; [void]$g.ColumnDefinitions.Add($c) }

        $ico = New-Object Windows.Controls.Image
        $ico.Width = 20; $ico.Height = 20; $ico.VerticalAlignment = 'Center'; $ico.HorizontalAlignment = 'Left'
        $ico.Source = Get-IconoInicio $p
        if (-not $p.Activo) { $ico.Opacity = 0.45 }
        [void]$g.Children.Add($ico)

        $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Object Windows.Thickness 0, 0, 10, 0
        $tn = New-Object Windows.Controls.TextBlock
        $tn.Text = $p.Nombre; $tn.FontSize = 13; $tn.TextTrimming = 'CharacterEllipsis'; $tn.ToolTip = $p.Exe
        $tn.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($p.Activo) { 'Text' } else { 'Muted' }))
        [void]$sp.Children.Add($tn)
        $det = @($p.Editor, $p.Nota) | Where-Object { $_ }
        if ($det) {
            $ts = New-Object Windows.Controls.TextBlock
            $ts.FontSize = 11; $ts.TextWrapping = 'Wrap'
            if ($p.Editor) { $r = New-Object Windows.Documents.Run $p.Editor; $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Muted'); $ts.Inlines.Add($r) }
            if ($p.Editor -and $p.Nota) { $r = New-Object Windows.Documents.Run '  ·  '; $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Faint'); $ts.Inlines.Add($r) }
            if ($p.Nota) {
                $r = New-Object Windows.Documents.Run $p.Nota
                # verde lo que conviene apagar (si sigue prendido), amarillo lo que conviene dejar
                $r.Foreground = if ($p.Tipo -eq 'apagar' -and $p.Activo) { $Colores.ok } elseif ($p.Tipo -eq 'dejar') { $Colores.warn } else { $Colores.muted }
                $ts.Inlines.Add($r)
            }
            [void]$sp.Children.Add($ts)
        }
        [Windows.Controls.Grid]::SetColumn($sp, 1); [void]$g.Children.Add($sp)

        # el mismo switch que "Iniciar con Windows" del pie, un poco más grande
        $sw = New-Object Windows.Controls.Border
        $sw.Width = 32; $sw.Height = 18; $sw.CornerRadius = New-Object Windows.CornerRadius 9; $sw.VerticalAlignment = 'Center'; $sw.Cursor = 'Hand'
        $sw.Background = if ($p.Activo) { $Colores.accent } else { $Colores.toggleOff }
        $sw.ToolTip = if ($p.Activo) { 'Se abre al prender la PC: tocá para apagarlo' } else { 'Apagado: tocá para que vuelva a abrirse al prender la PC' }
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width = 14; $dot.Height = 14; $dot.Fill = [Windows.Media.Brushes]::White; $dot.Margin = New-Object Windows.Thickness 2, 0, 2, 0
        $dot.HorizontalAlignment = if ($p.Activo) { 'Right' } else { 'Left' }
        $sw.Child = $dot
        $sw.Tag = $p
        $sw.Add_MouseLeftButtonUp({ Toggle-ProgramaInicio $this.Tag })
        [Windows.Controls.Grid]::SetColumn($sw, 2); [void]$g.Children.Add($sw)

        $b.Child = $g
        [void]$ui.IniLista.Children.Add($b)
    }
}

function Toggle-ProgramaInicio($p) {
    $prender = -not $p.Activo
    if ($p.Politica) {
        Show-Dialogo 'Programas de arranque' "$($p.Nombre) lo maneja una política de tu empresa o escuela: no se puede cambiar desde acá." 'OK' '' 'alerta' | Out-Null; return
    }
    if ($p.Colmena -eq 'HKLM' -and -not $EsAdminAhora) {
        Show-Dialogo 'Programas de arranque' "$($p.Nombre) está puesto para todos los usuarios de la PC: para cambiarlo hay que abrir el Optimizador con permisos de administrador." 'OK' '' 'alerta' | Out-Null; return
    }
    if (-not $prender -and $p.Tipo -eq 'dejar') {
        if (-not (Show-Dialogo "¿Apagar $($p.Nombre)?" "Parece ser del sistema, del sonido o del antivirus. Si lo apagás puede dejar de andar algo (por ejemplo, las teclas de volumen o la protección en tiempo real).`n`nSe vuelve a prender desde acá cuando quieras." 'Apagar igual' 'Cancelar' 'alerta')) { return }
    }
    $pos = $ui.IniScroll.VerticalOffset
    try {
        Set-ProgramaInicio $p $prender
        $aviso = if ($prender) { "$($p.Nombre) se va a abrir al prender la PC." } else { "Listo: $($p.Nombre) ya no se abre solo. Si está abierto ahora, sigue abierto hasta que lo cierres." }
    } catch { $aviso = "No se pudo cambiar $($p.Nombre): $($_.Exception.Message)" }
    Show-Inicio $aviso
    $ui.IniScroll.UpdateLayout(); $ui.IniScroll.ScrollToVerticalOffset($pos)   # que la lista no salte arriba
}

# ---------- pestaña Espacio: qué ocupa el disco y qué se puede liberar ----------
# Limpiar: categorías medidas en segundo plano, cada una con su casilla · Juegos: Steam y Epic por tamaño ·
# Carpetas: mide el disco entero (JVps.Escaner) y deja recorrerlo carpeta por carpeta. Desde Carpetas no se borra
# nada: solo se abre en el Explorador (son archivos personales, que los decida cada uno).
$esp = @{ Sub = 'limp'; Cats = $null; Juegos = $null; Marcas = @{}; Seleccion = 0.0; Midiendo = $false; Limpiando = $false
    Resultado = $null; Restos = @{}; Disco = $null; Unidades = $null; Unidad = $env:SystemDrive; Escaneos = @{}; Ruta = $null; Job = $null; JobAnal = $null }

function New-Texto([string]$texto, [double]$tam = 12, [string]$color = 'Text', [string]$peso = 'Normal') {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $texto; $tb.FontSize = $tam; $tb.FontWeight = $peso; $tb.TextTrimming = 'CharacterEllipsis'
    $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $color)
    $tb
}
function New-Glifo([int]$codigo, [string]$color = 'Muted', [double]$tam = 14) {
    $tb = New-Texto ([string][char]$codigo) $tam $color
    $tb.FontFamily = 'Segoe MDL2 Assets'; $tb.VerticalAlignment = 'Center'
    $tb
}
function New-Fila([double]$abajo = 6) {
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 10; $b.Padding = New-Object Windows.Thickness 12, 8, 12, 8
    $b.Margin = New-Object Windows.Thickness 0, 0, 0, $abajo
    $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
    $b
}
function New-Titulo([string]$texto, [string]$sub = '') {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = New-Object Windows.Thickness 2, 8, 0, 8
    [void]$sp.Children.Add((New-Texto $texto 10 'Muted' 'Bold'))
    if ($sub) { $t = New-Texto $sub 11 'Faint'; $t.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t) }
    $sp
}
function Add-Columnas($g, [string[]]$anchos) { foreach ($a in $anchos) { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $a; [void]$g.ColumnDefinitions.Add($c) } }
function Set-Col($el, [int]$col) { [Windows.Controls.Grid]::SetColumn($el, $col); $el }
function Open-Explorador([string]$ruta, [switch]$Seleccionar) {
    if ($ruta -match '^[A-Za-z]:$') { $ruta += '\' }
    try { if ($Seleccionar) { Start-Process explorer.exe "/select,`"$ruta`"" } else { Start-Process explorer.exe "`"$ruta`"" } } catch { }
}
# pastilla elegida/no elegida (las partes Limpiar/Juegos/Carpetas y los discos de Carpetas)
function Set-Pastilla($b, [bool]$sel) {
    if ($sel) { $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentSoft'); $b.Child.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Accent') }
    else { $b.Background = [Windows.Media.Brushes]::Transparent; $b.Child.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Muted') }
    $b.Child.FontWeight = if ($sel) { 'SemiBold' } else { 'Normal' }
}

function Show-Espacio {
    Set-EspSub $esp.Sub
    $esp.Disco = $null; Update-EspBarra
    if ($esp.Cats) { Show-Limpiar; Show-Juegos }   # repinta (por si cambió el tema)
    elseif (-not $esp.Midiendo) { Start-MedirEspacio }
}

function Set-EspSub([string]$s) {
    $esp.Sub = $s
    foreach ($x in @(@('limp', $ui.EspSegLimp, $ui.EspLimp), @('jue', $ui.EspSegJue, $ui.EspJue), @('carp', $ui.EspSegCarp, $ui.EspCarp))) {
        Set-Pastilla $x[1] ($x[0] -eq $s)
        $x[2].Visibility = if ($x[0] -eq $s) { 'Visible' } else { 'Collapsed' }
    }
    if ($s -eq 'carp') { Show-Unidades }
}
$ui.EspSegLimp.Add_MouseLeftButtonUp({ Set-EspSub 'limp' })
$ui.EspSegJue.Add_MouseLeftButtonUp({ Set-EspSub 'jue' })
$ui.EspSegCarp.Add_MouseLeftButtonUp({ Set-EspSub 'carp' })

# barras de los discos: usado, lo elegido para liberar (verde, en el de Windows) y libre
function Update-EspBarra {
    if (-not $esp.Disco) { $esp.Disco = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object Size | Sort-Object DeviceID) }
    $ui.EspDiscos.Children.Clear()
    foreach ($d in $esp.Disco) {
        $tot = [double]$d.Size; $libre = [double]$d.FreeSpace; $usado = $tot - $libre
        $win_ = $d.DeviceID -eq $env:SystemDrive
        $lib = if ($win_) { [math]::Min($usado, $esp.Seleccion) } else { 0.0 }
        $fila = New-Object Windows.Controls.StackPanel; $fila.Margin = New-Object Windows.Thickness 0, 0, 0, 7
        $cab = New-Object Windows.Controls.DockPanel
        $lt = New-Texto ('{0} libres de {1}' -f (Format-Tam $libre), (Format-Tam $tot)) 11.5
        $lt.Foreground = if ($libre / $tot -lt 0.1) { $Colores.err } elseif ($libre / $tot -lt 0.2) { $Colores.warn } else { $Colores.muted }
        [Windows.Controls.DockPanel]::SetDock($lt, 'Right'); [void]$cab.Children.Add($lt)
        $nom = if ($win_) { 'Windows' } elseif (([string]$d.VolumeName).Trim()) { ([string]$d.VolumeName).Trim() } else { 'Disco local' }
        $nt = New-Object Windows.Controls.TextBlock; $nt.FontSize = 12.5; $nt.TextTrimming = 'CharacterEllipsis'
        $r = New-Object Windows.Documents.Run $d.DeviceID; $r.FontWeight = 'SemiBold'; $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Text'); $nt.Inlines.Add($r)
        $r = New-Object Windows.Documents.Run "  $nom"; $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Muted'); $nt.Inlines.Add($r)
        [void]$cab.Children.Add($nt)
        [void]$fila.Children.Add($cab)
        # la barra en columnas proporcionales: no depende del ancho medido, se acomoda sola
        $bar = New-Object Windows.Controls.Grid; $bar.Height = 8; $bar.Margin = New-Object Windows.Thickness 0, 5, 0, 0
        Add-Columnas $bar ('{0}*' -f [math]::Round(($usado - $lib) / $tot, 4).ToString([Globalization.CultureInfo]::InvariantCulture)),
            ('{0}*' -f [math]::Round($lib / $tot, 4).ToString([Globalization.CultureInfo]::InvariantCulture)),
            ('{0}*' -f [math]::Round($libre / $tot, 4).ToString([Globalization.CultureInfo]::InvariantCulture))
        $fondo = New-Object Windows.Controls.Border; $fondo.CornerRadius = New-Object Windows.CornerRadius 4; $fondo.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Line')
        [Windows.Controls.Grid]::SetColumnSpan($fondo, 3); [void]$bar.Children.Add($fondo)
        $u = New-Object Windows.Controls.Border; $u.CornerRadius = New-Object Windows.CornerRadius 4, 0, 0, 4; $u.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Accent')
        if ($lib -le 0) { $u.CornerRadius = New-Object Windows.CornerRadius 4 }
        [void]$bar.Children.Add($u)
        if ($lib -gt 0) { $l = New-Object Windows.Controls.Border; $l.Background = $Colores.ok; $l.CornerRadius = New-Object Windows.CornerRadius 0, 4, 4, 0; [void]$bar.Children.Add((Set-Col $l 1)) }
        [void]$fila.Children.Add($bar)
        [void]$ui.EspDiscos.Children.Add($fila)
    }
    $ui.EspLeyenda.Inlines.Clear()
    $partes = @(, @($Colores.accent, 'Usado'))   # la coma: si no, PowerShell aplana el par
    if ($esp.Seleccion -gt 0) { $partes += , @($Colores.ok, "Se liberan $(Format-Tam $esp.Seleccion) de $env:SystemDrive") }
    $partes += , @($null, 'Libre')
    foreach ($x in $partes) {
        $r = New-Object Windows.Documents.Run '●  '
        if ($x[0]) { $r.Foreground = $x[0] } else { $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Line') }
        $ui.EspLeyenda.Inlines.Add($r)
        $r = New-Object Windows.Documents.Run "$($x[1])      "
        $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Muted')
        $ui.EspLeyenda.Inlines.Add($r)
    }
}

# ---- segundo plano: un runspace por tarea, avisa por la cola ($sync.Q) igual que las acciones ----
function New-RunspaceEsp {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('EscanerCs', $EscanerCs)
    $rs.SessionStateProxy.SetVariable('Raiz', $Raiz)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $ps
}
function Close-JobEsp($ps) { if ($ps) { try { $ps.Runspace.Dispose(); $ps.Dispose() } catch { } } }

function Start-MedirEspacio {
    $esp.Midiendo = $true
    $ui.EspLimpEstado.Text = 'Midiendo cuánto ocupa cada cosa...'; $ui.EspJueEstado.Text = 'Buscando juegos...'
    $ps = New-RunspaceEsp; $esp.Job = $ps
    [void]$ps.AddScript($FnEspacio.ToString() + "`n" + @'
$ErrorActionPreference = 'SilentlyContinue'
try { $c = @(Get-CategoriasEspacio); $j = @(Get-JuegosInstalados); $sync.Q.Enqueue(@{ Tipo = 'espmed'; C = $c; J = $j }) }
catch { $sync.Q.Enqueue(@{ Tipo = 'espmed'; Error = $_.Exception.Message }) }
'@)
    [void]$ps.BeginInvoke()
}
function Handle-EspMed($m) {
    Close-JobEsp $esp.Job; $esp.Job = $null; $esp.Midiendo = $false
    if ($m.Error) { $ui.EspLimpEstado.Text = "No se pudo medir: $($m.Error)"; return }
    $esp.Cats = $m.C; $esp.Juegos = $m.J
    foreach ($c in $esp.Cats) {
        if (-not $esp.Marcas.ContainsKey($c.Id)) { $esp.Marcas[$c.Id] = ($c.Grupo -eq 'seguro') }
        # lo que quedó la última vez que se limpió lo está usando un programa abierto: no se ofrece de nuevo
        # (si después se juntó más, se ofrece solo lo nuevo)
        $resto = [long]$esp.Restos[$c.Id]
        if ($resto -gt 0) { $c.Resto = [math]::Min($resto, [long]$c.Tam); $c.Libre = [long]$c.Tam - $c.Resto; if ($c.Libre -lt 1MB) { $c.Libre = 0 } }
    }
    Show-Limpiar; Show-Juegos
    if ($Captura -and $Vista -in 'espacio', 'espacio-juegos') { $script:CapturaLista = Get-Date }
}

# ---- Limpiar ----
function Get-EspElegibles { @($esp.Cats | Where-Object { -not $_.Motivo -and $_.Libre -gt 0 }) }
function Get-EspElegidas { @(Get-EspElegibles | Where-Object { $esp.Marcas[$_.Id] }) }

function Show-Limpiar {
    $ui.EspLimpEstado.Text = ''
    $ui.EspLista.Children.Clear()
    $grupos = @(
        @('LIMPIEZA SEGURA', 'Se rehace solo: no perdés nada.', @($esp.Cats | Where-Object Grupo -eq 'seguro')),
        @('REVISALO ANTES DE MARCARLO', 'Libera mucho, pero cada uno tiene su contra: leela antes.', @($esp.Cats | Where-Object Grupo -eq 'revisar'))
    )
    foreach ($g in $grupos) {
        if (-not $g[2]) { continue }
        [void]$ui.EspLista.Children.Add((New-Titulo $g[0] $g[1]))
        foreach ($c in $g[2]) { [void]$ui.EspLista.Children.Add((New-FilaCategoria $c)) }
    }
    Update-EspSeleccion
}

function New-FilaCategoria($c) {
    $b = New-Fila
    $ok = -not $c.Motivo -and $c.Libre -gt 0
    $g = New-Object Windows.Controls.Grid; Add-Columnas $g '30', '*', 'Auto'
    # casilla propia (la de WPF no sigue el tema): cuadrado redondeado con tilde
    $cb = New-Object Windows.Controls.Border
    $cb.Width = 18; $cb.Height = 18; $cb.CornerRadius = New-Object Windows.CornerRadius 5; $cb.VerticalAlignment = 'Center'; $cb.HorizontalAlignment = 'Left'
    $tic = New-Glifo 0xE73E 'Text' 11; $tic.Foreground = [Windows.Media.Brushes]::White; $tic.HorizontalAlignment = 'Center'
    $cb.Child = $tic
    [void]$g.Children.Add($cb)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = New-Object Windows.Thickness 0, 0, 12, 0; $sp.VerticalAlignment = 'Center'
    [void]$sp.Children.Add((New-Texto $c.Nombre 13))
    $d = New-Texto $(if ($c.Motivo) { $c.Motivo } else { $c.Desc }) 11 'Muted'
    $d.TextWrapping = 'Wrap'; $d.TextTrimming = 'None'
    if ($c.Motivo) { $d.Foreground = $Colores.warn }
    [void]$sp.Children.Add($d)
    if ($c.Resto -gt 1MB) {
        $u = New-Texto "$(Format-Tam $c.Resto) en uso por un programa abierto: se borra cuando lo cierres o al reiniciar" 11 'Faint'
        $u.TextWrapping = 'Wrap'; $u.TextTrimming = 'None'
        [void]$sp.Children.Add($u)
    }
    [void]$g.Children.Add((Set-Col $sp 1))
    $t = New-Texto $(if ($c.Libre -gt 0) { Format-Tam $c.Libre } elseif ($c.Resto -gt 0) { 'En uso' } else { 'Vacío' }) 13 $(if ($c.Libre -gt 0) { 'Text' } else { 'Faint' }) 'SemiBold'
    $t.VerticalAlignment = 'Center'
    [void]$g.Children.Add((Set-Col $t 2))
    $b.Child = $g
    $b.Tag = @{ C = $c; Casilla = $cb; Ok = $ok }
    if ($ok) {
        $b.Cursor = 'Hand'
        $b.Add_MouseLeftButtonUp({
            if ($esp.Limpiando) { return }
            $id = $this.Tag.C.Id; $esp.Marcas[$id] = -not $esp.Marcas[$id]; $esp.Resultado = $null
            Set-Casilla $this.Tag; Update-EspSeleccion
        })
    } else { $b.Opacity = 0.55 }
    Set-Casilla $b.Tag
    $b
}
function Set-Casilla($t) {
    $on = $t.Ok -and $esp.Marcas[$t.C.Id]
    $t.Casilla.Child.Visibility = if ($on) { 'Visible' } else { 'Hidden' }
    if ($on) { $t.Casilla.Background = $Colores.accent; $t.Casilla.BorderThickness = New-Object Windows.Thickness 0 }
    else {
        $t.Casilla.Background = [Windows.Media.Brushes]::Transparent; $t.Casilla.BorderThickness = New-Object Windows.Thickness 1.5
        $t.Casilla.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Muted')
    }
}
function Update-EspSeleccion {
    $sel = Get-EspElegidas
    $esp.Seleccion = [double](($sel | Measure-Object Libre -Sum).Sum)
    $ui.EspBtnLiberar.Content = if ($esp.Seleccion) { "Liberar $(Format-Tam $esp.Seleccion)" } else { 'Liberar' }
    $ui.EspBtnLiberar.IsEnabled = $esp.Seleccion -gt 0 -and -not $esp.Limpiando
    if (-not $esp.Limpiando) {
        if ($esp.Resultado) { $ui.EspSel.Text = $esp.Resultado; $ui.EspSel.Foreground = if ($esp.Resultado -like 'Listo*') { $Colores.ok } else { $Colores.warn } }
        else { $ui.EspSel.Text = "$($sel.Count) de $(@(Get-EspElegibles).Count) elegidas"; $ui.EspSel.Foreground = $Colores.muted }
    }
    Update-EspBarra
}

$ui.EspBtnLiberar.Add_Click({
    $sel = Get-EspElegidas
    if (-not $sel) { return }
    $lineas = foreach ($c in $sel) { "•  $($c.Nombre) ($(Format-Tam $c.Libre))" + $(if ($c.Grupo -eq 'revisar') { "`n     $($c.Desc)" }) }
    $txt = "Se va a borrar:`n" + ($lineas -join "`n") + "`n`nLo que esté en uso en este momento se saltea. No toca tus documentos, fotos ni juegos."
    if (Show-Dialogo "¿Liberar $(Format-Tam $esp.Seleccion)?" $txt 'Liberar' 'Cancelar' 'pregunta') { Start-LimpiarEspacio $sel }
})

function Start-LimpiarEspacio($sel) {
    $esp.Limpiando = $true; $esp.Resultado = $null
    $ui.EspBtnLiberar.Visibility = 'Collapsed'; $ui.EspProg.Visibility = 'Visible'; $ui.EspProg.Value = 0
    $ui.EspSel.Text = 'Arrancando...'; $ui.EspSel.Foreground = $Colores.muted
    $ps = New-RunspaceEsp; $esp.Job = $ps
    $ps.Runspace.SessionStateProxy.SetVariable('Elegidas', $sel)
    [void]$ps.AddScript($FnEspacio.ToString() + "`n" + @'
$ErrorActionPreference = 'SilentlyContinue'
try { $r = @(Invoke-LimpiarEspacio $Elegidas) } catch { $r = @() }
$sync.Q.Enqueue(@{ Tipo = 'espfin'; R = $r })
'@)
    [void]$ps.BeginInvoke()
}
function Handle-EspProg($m) {
    $ui.EspProg.Value = [math]::Round(($m.I - 1) * 100.0 / [math]::Max(1, $m.N))
    $ui.EspSel.Text = "Borrando $($m.L)...  ($($m.I) de $($m.N))"
}
function Handle-EspFin($m) {
    Close-JobEsp $esp.Job; $esp.Job = $null; $esp.Limpiando = $false
    $tot = [double](($m.R | ForEach-Object { $_.Lib } | Measure-Object -Sum).Sum)
    $ui.EspProg.Visibility = 'Collapsed'; $ui.EspBtnLiberar.Visibility = 'Visible'
    foreach ($r in $m.R) { $esp.Restos[$r.Id] = [long]$r.Resto }
    $esp.Resultado = if ($tot -ge 1MB) { "Listo: liberaste $(Format-Tam $tot)" } else { 'No se pudo borrar: lo está usando un programa abierto' }
    # también queda en Actividad, como las otras acciones
    if ($ui.Log.Document.Blocks.Count) { Add-Line '' }
    Add-Line 'LIBERAR ESPACIO' 'title'
    foreach ($r in $m.R) { Add-Line ('  {0,-44}{1,10}' -f $r.Nombre, (Format-Tam $r.Lib)) $(if ($r.Lib -gt 0) { 'ok' } else { 'dim' }) }
    Add-Line "Liberado: $(Format-Tam $tot)" 'title'
    Play-Listo; Update-Stats
    $esp.Disco = $null
    Start-MedirEspacio   # vuelve a medir: lo que estaba en uso sigue apareciendo con lo que quedó
}

# ---- Juegos ----
function Get-HaceCuanto($f) {
    if (-not $f) { return '' }
    $d = [math]::Floor(((Get-Date) - $f).TotalDays)
    if ($d -lt 1) { 'jugado hoy' } elseif ($d -lt 2) { 'jugado ayer' } elseif ($d -lt 31) { "jugado hace $d días" }
    elseif ($d -lt 365) { $m = [math]::Floor($d / 30); "jugado hace $m $(if ($m -eq 1) { 'mes' } else { 'meses' })" } else { 'jugado hace más de un año' }
}
function Show-Juegos {
    $ui.EspJueLista.Children.Clear()
    $js = @($esp.Juegos)
    if (-not $js) { $ui.EspJueEstado.Text = 'No encontré juegos de Steam ni de Epic.'; return }
    $tot = ($js | Measure-Object Tam -Sum).Sum
    $viejos = @($js | Where-Object { $_.Jugado -and ((Get-Date) - $_.Jugado).TotalDays -gt 180 })
    $ui.EspJueEstado.Text = "$($js.Count) juegos de Steam y Epic: $(Format-Tam $tot) en total." +
        $(if ($viejos) { " Hace más de 6 meses que no abrís $($viejos.Count) ($(Format-Tam ($viejos | Measure-Object Tam -Sum).Sum))." })
    foreach ($j in $js) {
        $b = New-Fila 5
        $g = New-Object Windows.Controls.Grid; Add-Columnas $g '*', 'Auto'
        $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = New-Object Windows.Thickness 0, 0, 12, 0
        [void]$sp.Children.Add((New-Texto $j.Nombre 13))
        $sub = New-Object Windows.Controls.TextBlock; $sub.FontSize = 11; $sub.TextTrimming = 'CharacterEllipsis'
        $u = try { Split-Path $j.Ruta -Qualifier } catch { '' }
        $r = New-Object Windows.Documents.Run $(if ($u) { "$($j.Tienda) · $u" } else { $j.Tienda })
        $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Muted'); $sub.Inlines.Add($r)
        $cuando = if ($j.Tienda -eq 'Steam') { if ($j.Jugado) { Get-HaceCuanto $j.Jugado } else { 'nunca jugado' } }
        if ($cuando) {
            $r = New-Object Windows.Documents.Run "  ·  $cuando"
            # lo que hace mucho no se abre, en amarillo: son los candidatos a desinstalar
            if (-not $j.Jugado -or ((Get-Date) - $j.Jugado).TotalDays -gt 180) { $r.Foreground = $Colores.warn } else { $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'Muted') }
            $sub.Inlines.Add($r)
        }
        [void]$sp.Children.Add($sub)
        [void]$g.Children.Add($sp)
        $der = New-Object Windows.Controls.StackPanel; $der.VerticalAlignment = 'Center'
        $t = New-Texto (Format-Tam $j.Tam) 13 'Text' 'SemiBold'; $t.HorizontalAlignment = 'Right'
        [void]$der.Children.Add($t)
        $links = New-Object Windows.Controls.StackPanel; $links.Orientation = 'Horizontal'; $links.HorizontalAlignment = 'Right'
        foreach ($l in @(@('Carpeta', 'carpeta'), @($(if ($j.Tienda -eq 'Steam') { 'Desinstalar' } else { 'Abrir Epic' }), 'quitar'))) {
            $lk = New-Texto $l[0] 11 'Accent'; $lk.Cursor = 'Hand'; $lk.Margin = New-Object Windows.Thickness 10, 1, 0, 0
            $lk.Tag = @{ J = $j; Que = $l[1] }
            $lk.Add_MouseLeftButtonUp({
                $x = $this.Tag
                if ($x.Que -eq 'carpeta') { Open-Explorador $x.J.Ruta }
                elseif ($x.J.Tienda -eq 'Steam') { try { Start-Process "steam://uninstall/$($x.J.Id)" } catch { } }   # Steam pregunta antes de borrar
                else { try { Start-Process 'com.epicgames.launcher://' } catch { } }
            })
            [void]$links.Children.Add($lk)
        }
        [void]$der.Children.Add($links)
        [void]$g.Children.Add((Set-Col $der 1))
        $b.Child = $g
        [void]$ui.EspJueLista.Children.Add($b)
    }
}

# ---- Carpetas: analizador del disco ----
function Show-Unidades {
    if (-not $esp.Unidades) { $esp.Unidades = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID | ForEach-Object DeviceID) }
    $ui.EspUnidades.Children.Clear()
    foreach ($u in $esp.Unidades) {
        $p = New-Object Windows.Controls.Border
        $p.CornerRadius = New-Object Windows.CornerRadius 7; $p.Padding = New-Object Windows.Thickness 11, 4, 11, 4; $p.Margin = New-Object Windows.Thickness 0, 0, 4, 0; $p.Cursor = 'Hand'
        $p.Child = New-Texto $u 12
        Set-Pastilla $p ($u -eq $esp.Unidad)
        $p.Tag = $u
        $p.Add_MouseLeftButtonUp({ if ($esp.JobAnal) { return }; $esp.Unidad = $this.Tag; Show-Unidades })
        [void]$ui.EspUnidades.Children.Add($p)
    }
    Show-Analisis
}
function Show-Analisis {
    $e = $esp.Escaneos[$esp.Unidad]
    $ui.EspBtnAnalizar.Content = if ($esp.JobAnal) { 'Cancelar' } elseif ($e) { 'Volver a analizar' } else { "Analizar $($esp.Unidad)" }
    if ($esp.JobAnal) { return }
    if ($e) {
        $r = if ($esp.Ruta -and $esp.Ruta.StartsWith($esp.Unidad, [StringComparison]::OrdinalIgnoreCase)) { $esp.Ruta } else { $esp.Unidad }
        Show-Carpeta $r
    } else {
        $ui.EspMigas.Children.Clear(); $ui.EspCarpLista.Children.Clear()
        $ui.EspCarpEstado.Text = "Mide todas las carpetas de $($esp.Unidad) para que veas qué ocupa más y entres a cada una. Tarda entre medio minuto y unos minutos, según el disco. No borra nada."
    }
}
$ui.EspBtnAnalizar.Add_Click({
    if ($esp.JobAnal) { if ($sync.Esc) { $sync.Esc.Cancelar = $true }; return }
    Start-Analisis
})
function Start-Analisis {
    $u = $esp.Unidad
    $esp.Escaneos.Remove($u); $esp.Ruta = $null; $sync.Esc = $null
    $ps = New-RunspaceEsp; $esp.JobAnal = $ps
    $ps.Runspace.SessionStateProxy.SetVariable('Unidad', $u)
    [void]$ps.AddScript(@'
if (-not ('JVps.Escaner' -as [type])) { Add-Type -TypeDefinition $EscanerCs }
$e = New-Object JVps.Escaner
$sync.Esc = $e
try { $e.Escanear($Unidad + '\') } catch { }
$sync.Q.Enqueue(@{ Tipo = 'espanal'; U = $Unidad; E = $e })
'@)
    [void]$ps.BeginInvoke()
    $ui.EspMigas.Children.Clear(); $ui.EspCarpLista.Children.Clear()
    $ui.EspCarpEstado.Text = "Preparando el análisis de $u..."
    $ui.EspBtnAnalizar.Content = 'Cancelar'
    $script:EspTimer.Start()
}
# progreso del análisis: lo lee del escáner que corre en segundo plano
$script:EspTimer = New-Object Windows.Threading.DispatcherTimer
$script:EspTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:EspTimer.Add_Tick({
    if (-not $esp.JobAnal) { $script:EspTimer.Stop(); return }
    $e = $sync.Esc
    if (-not $e) { return }
    $act = [string]$e.Actual
    if ($act.Length -gt 52) { $act = '...' + $act.Substring($act.Length - 49) }
    $ui.EspCarpEstado.Text = ("Analizando {0}: {1} en {2:N0} archivos" -f $esp.Unidad, (Format-Tam $e.Bytes), $e.Archivos) + "`n$act"
})
function Handle-EspAnal($m) {
    Close-JobEsp $esp.JobAnal; $esp.JobAnal = $null; $script:EspTimer.Stop(); $sync.Esc = $null
    $e = $m.E
    if ($e.Cancelar) { Show-Analisis; $ui.EspCarpEstado.Text = 'Análisis cancelado.'; return }
    $esp.Escaneos[$m.U] = $e
    if ($esp.Sub -eq 'carp' -and $esp.Unidad -eq $m.U) { Show-Analisis }
    if ($Captura -and $Vista -eq 'espacio-carpetas') { $script:CapturaLista = Get-Date }
}

function Show-Carpeta([string]$ruta) {
    $e = $esp.Escaneos[$esp.Unidad]
    if (-not $e) { return }
    $esp.Ruta = $ruta
    $total = [double]$(if ($e.Carpetas.ContainsKey($ruta)) { $e.Carpetas[$ruta] } else { 0 })
    $nota = if ($e.SinPermiso -gt 0 -and -not $EsAdminAhora) { ' · sin permisos de administrador hay carpetas que no se pudieron medir' } else { '' }
    $ui.EspCarpEstado.Text = ('{0:N0} archivos en {1}{2}. Tocá una carpeta para entrar.' -f $e.Archivos, (Format-Tam $e.Bytes), $nota)

    # migas: C: › Users › User (cada una lleva a esa carpeta)
    $ui.EspMigas.Children.Clear()
    $partes = $ruta -split '\\'; $acum = ''
    for ($i = 0; $i -lt $partes.Count; $i++) {
        $acum = if ($i) { "$acum\$($partes[$i])" } else { $partes[0] }
        $ult = $i -eq $partes.Count - 1
        if ($i) { $s = New-Texto '  ›  ' 12 'Faint'; [void]$ui.EspMigas.Children.Add($s) }
        $t = New-Texto $partes[$i] 12 $(if ($ult) { 'Text' } else { 'Accent' }) $(if ($ult) { 'SemiBold' } else { 'Normal' })
        if (-not $ult) { $t.Cursor = 'Hand'; $t.Tag = $acum; $t.Add_MouseLeftButtonUp({ Show-Carpeta $this.Tag }) }
        [void]$ui.EspMigas.Children.Add($t)
    }

    $ui.EspCarpLista.Children.Clear()
    $hijos = if ($e.Hijos.ContainsKey($ruta)) { @($e.Hijos[$ruta] | Sort-Object { $e.Carpetas[$_] } -Descending) } else { @() }
    $suma = 0.0; foreach ($h in $hijos) { $suma += $e.Carpetas[$h] }
    [void]$ui.EspCarpLista.Children.Add((New-Titulo ('ESTA CARPETA OCUPA {0}' -f (Format-Tam $total))))
    $n = 0
    foreach ($h in $hijos) {
        if (++$n -gt 15) { break }
        $tam = [double]$e.Carpetas[$h]
        [void]$ui.EspCarpLista.Children.Add((New-FilaCarpeta (Split-Path $h -Leaf) $h $tam $total $e.Hijos.ContainsKey($h)))
    }
    if ($hijos.Count -gt 15) {
        $resto = 0.0; for ($k = 15; $k -lt $hijos.Count; $k++) { $resto += $e.Carpetas[$hijos[$k]] }
        $t = New-Texto ("y {0} carpetas más: {1}" -f ($hijos.Count - 15), (Format-Tam $resto)) 11 'Faint'; $t.Margin = New-Object Windows.Thickness 4, 0, 0, 6
        [void]$ui.EspCarpLista.Children.Add($t)
    }
    $sueltos = $total - $suma
    if ($sueltos -gt 50MB) { [void]$ui.EspCarpLista.Children.Add((New-FilaCarpeta 'Archivos sueltos en esta carpeta' $ruta $sueltos $total $false 0xE7C3)) }

    $grandes = @($e.Grandes | Where-Object { $_.Key.StartsWith("$ruta\", [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 8)
    if ($grandes) {
        [void]$ui.EspCarpLista.Children.Add((New-Titulo 'ARCHIVOS MÁS GRANDES' 'Tocá uno para verlo en su carpeta.'))
        foreach ($f in $grandes) {
            $dir = Split-Path $f.Key
            $rel = if ($dir.Length -gt $ruta.Length) { $dir.Substring($ruta.Length).TrimStart('\') } else { '' }
            [void]$ui.EspCarpLista.Children.Add((New-FilaCarpeta (Split-Path $f.Key -Leaf) $f.Key ([double]$f.Value) $total $false 0xE7C3 $rel -Archivo))
        }
    }
    $ui.EspCarpScroll.ScrollToTop()
}

# fila del analizador: ícono, nombre, barra (qué parte de la carpeta de arriba es), tamaño y "abrir en el Explorador"
function New-FilaCarpeta([string]$nombre, [string]$ruta, [double]$tam, [double]$total, [bool]$entrable, [int]$glifo = 0xF12B, [string]$detalle = '', [switch]$Archivo) {
    $b = New-Fila 5; $b.Padding = New-Object Windows.Thickness 10, 7, 8, 7
    $g = New-Object Windows.Controls.Grid; Add-Columnas $g '26', '*', 'Auto', '30'
    [void]$g.Children.Add((New-Glifo $glifo $(if ($entrable) { 'Accent' } else { 'Muted' }) 14))
    $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Object Windows.Thickness 0, 0, 12, 0
    [void]$sp.Children.Add((New-Texto $nombre 12.5))
    if ($detalle) { [void]$sp.Children.Add((New-Texto $detalle 10.5 'Faint')) }
    # redondeado: un 0,00001 se escribiría "1E-05*" y la grilla no lo entiende
    $p = if ($total -gt 0) { [math]::Round([math]::Max(0.0, [math]::Min(1.0, $tam / $total)), 3) } else { 0.0 }
    $bar = New-Object Windows.Controls.Grid; $bar.Height = 4; $bar.Margin = New-Object Windows.Thickness 0, 5, 0, 0
    Add-Columnas $bar "$p*", "$(1 - $p)*"
    $fondo = New-Object Windows.Controls.Border; $fondo.CornerRadius = New-Object Windows.CornerRadius 2; $fondo.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Line')
    [Windows.Controls.Grid]::SetColumnSpan($fondo, 2); [void]$bar.Children.Add($fondo)
    $lleno = New-Object Windows.Controls.Border; $lleno.CornerRadius = New-Object Windows.CornerRadius 2; $lleno.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Accent')
    [void]$bar.Children.Add($lleno)
    [void]$sp.Children.Add($bar)
    [void]$g.Children.Add((Set-Col $sp 1))
    $t = New-Texto (Format-Tam $tam) 12.5 'Text' 'SemiBold'; $t.VerticalAlignment = 'Center'; $t.ToolTip = '{0:N0}% de la carpeta' -f ($p * 100)
    [void]$g.Children.Add((Set-Col $t 2))
    $ab = New-Glifo 0xE8A7 'Muted' 12; $ab.HorizontalAlignment = 'Right'; $ab.Cursor = 'Hand'
    $ab.ToolTip = if ($Archivo) { 'Mostrar en su carpeta' } else { 'Abrir en el Explorador' }
    $ab.Tag = @{ R = $ruta; A = [bool]$Archivo }
    $ab.Add_MouseLeftButtonUp({ $x = $this.Tag; if ($x.A) { Open-Explorador $x.R -Seleccionar } else { Open-Explorador $x.R }; $_.Handled = $true })
    [void]$g.Children.Add((Set-Col $ab 3))
    $b.Child = $g
    $b.Tag = @{ R = $ruta; A = [bool]$Archivo; E = $entrable }
    $b.Cursor = 'Hand'
    $b.Add_MouseLeftButtonUp({
        $x = $this.Tag
        if ($x.E) { Show-Carpeta $x.R } elseif ($x.A) { Open-Explorador $x.R -Seleccionar } else { Open-Explorador $x.R }
    })
    $b
}

# ---------- pestaña Mi PC: especificaciones ----------
# Se junta en segundo plano (WMI tarda un segundo) y queda guardado: cada dato es T (qué), V (cuál) y S (detalle)
function Start-MiPc {
    $ui.PcEstado.Text = 'Revisando tu PC...'
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script:MiPcJob = $ps
    [void]$ps.AddScript({
        $ErrorActionPreference = 'SilentlyContinue'
        $d = New-Object Collections.ArrayList
        function Dato($t, $v, $s) { [void]$d.Add(@{ T = $t; V = ([string]$v).Trim(); S = $s }) }

        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        Dato 'Procesador' ($cpu.Name -replace '\s+', ' ') ('{0} núcleos · {1} hilos · hasta {2:N1} GHz' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, ($cpu.MaxClockSpeed / 1000))

        # placas de video reales (sin los adaptadores virtuales de escritorio remoto, etc.)
        $smi = (Get-Command nvidia-smi).Source
        $clase = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' | ForEach-Object { Get-ItemProperty $_.PSPath })
        foreach ($g in @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Mirage|Meta|Indirect' })) {
            # VRAM: nvidia-smi o el registro; AdapterRAM de Windows se queda trabado en 4 GB
            $vram = $null
            if ($smi -and $g.Name -match 'NVIDIA') { $vram = ([double]([JVps.Consola]::Correr($smi, '--query-gpu=memory.total --format=csv,noheader,nounits', 10000) | Select-Object -First 1)) / 1024 }
            if (-not $vram) {
                $q = ($clase | Where-Object { $_.DriverDesc -eq $g.Name } | Select-Object -First 1).'HardwareInformation.qwMemorySize'
                $vram = if ($q) { [double]$q / 1GB } elseif ($g.AdapterRAM) { [double]$g.AdapterRAM / 1GB }
            }
            $det = @()
            if ($vram) { $det += '{0:N0} GB de VRAM' -f $vram }
            if ($g.DriverVersion) { $det += 'driver ' + $g.DriverVersion + $(if ($g.DriverDate) { ' (' + $g.DriverDate.ToString('dd/MM/yyyy') + ')' }) }
            Dato 'Placa de video' $g.Name ($det -join ' · ')
        }

        $mods = @(Get-CimInstance Win32_PhysicalMemory)
        $total = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
        $tipo = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'DDR5' }[[int]$mods[0].SMBIOSMemoryType]
        $mhz = $mods[0].ConfiguredClockSpeed
        $pn = ([string]$mods[0].PartNumber).Trim()
        $nominal = if ($pn -match '(?<!\d)(2133|2400|2666|2933|3000|3200|3466|3600|4000|4400|4800|5200|5600|6000|6400|7200|8000)(?!\d)') { [int]$Matches[1] }
        $det = @(('{0} × {1:N0} GB' -f $mods.Count, ($mods[0].Capacity / 1GB)), $(if ($nominal -and $nominal -gt $mhz + 50) { "$mhz MHz (hecha para $nominal)" } else { "$mhz MHz" }))
        $marca = (([string]$mods[0].Manufacturer).Trim() + ' ' + $pn).Trim()
        if ($marca -and $marca -notmatch '^(Unknown|0+)') { $det += $marca }
        Dato 'Memoria RAM' ('{0:N0} GB {1}' -f $total, $tipo) ($det -join ' · ')

        $bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
        Dato 'Placa madre' "$($bb.Manufacturer) $($bb.Product)" ('BIOS {0}{1}' -f $bios.SMBIOSBIOSVersion, $(if ($bios.ReleaseDate) { ' (' + $bios.ReleaseDate.ToString('dd/MM/yyyy') + ')' }))

        # discos: consulta CIM directa (Get-PhysicalDisk/Get-Partition cargan un módulo que tarda ~10 s)
        # MediaType 3 = HDD, 4 = SSD · BusType 17 = NVMe
        $ns = 'root\Microsoft\Windows\Storage'
        $particiones = @(Get-CimInstance -Namespace $ns -ClassName MSFT_Partition | Where-Object { $_.DriveLetter -and [int][char]$_.DriveLetter -ne 0 })
        foreach ($pd in @(Get-CimInstance -Namespace $ns -ClassName MSFT_PhysicalDisk | Where-Object Size | Sort-Object { [int]$_.DeviceId })) {
            $tipoD = switch ([int]$pd.MediaType) { 4 { if ([int]$pd.BusType -eq 17) { 'SSD NVMe' } else { 'SSD' } } 3 { 'Disco rígido (HDD)' } default { 'Disco' } }
            $letras = @($particiones | Where-Object { [string]$_.DiskNumber -eq [string]$pd.DeviceId } | ForEach-Object { "$($_.DriveLetter):" }) -join ' '
            Dato 'Disco' $pd.FriendlyName (('{0:N0} GB · {1}' -f ($pd.Size / 1GB), $tipoD) + $(if ($letras) { " · $letras" }))
        }

        Add-Type -AssemblyName System.Windows.Forms
        $mon = Get-CimInstance Win32_VideoController | Where-Object CurrentHorizontalResolution | Select-Object -First 1
        $n = [Windows.Forms.Screen]::AllScreens.Count
        Dato 'Monitor' ('{0} × {1} a {2} Hz' -f $mon.CurrentHorizontalResolution, $mon.CurrentVerticalResolution, $mon.CurrentRefreshRate) $(if ($n -gt 1) { "$n monitores (este es el principal)" } else { '1 monitor' })

        $os = Get-CimInstance Win32_OperatingSystem
        $rv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        # Windows 11 sigue diciendo "Windows 10" en el registro: el número de compilación es el que manda
        $nombre = ($os.Caption -replace '^Microsoft\s+', '')
        Dato 'Windows' $nombre ('versión {0} · compilación {1}.{2} · instalado el {3}' -f $rv.DisplayVersion, $rv.CurrentBuild, $rv.UBR, $os.InstallDate.ToString('dd/MM/yyyy'))

        # red: la conexión con puerta de enlace (salida a internet), por .NET: Get-NetRoute tarda ~7 s en cargar
        $a = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
            $_.OperationalStatus -eq 'Up' -and @($_.GetIPProperties().GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and "$($_.Address)" -ne '0.0.0.0' }).Count
        } | Select-Object -First 1
        if ($a) {
            $wifi = "$($a.NetworkInterfaceType)" -eq 'Wireless80211'
            $vel = if ($a.Speed -ge 1e9) { '{0:N0} Gbps' -f ($a.Speed / 1e9) } else { '{0:N0} Mbps' -f ($a.Speed / 1e6) }
            Dato 'Red' $a.Description ('{0} · conectado a {1}' -f $(if ($wifi) { 'Wi-Fi' } else { 'Cable' }), $vel)
        }
        $sync.Q.Enqueue(@{ Tipo = 'mipc'; D = $d.ToArray() })
    })
    [void]$ps.BeginInvoke()
}

function Handle-MiPc($m) {
    if ($script:MiPcJob) { $script:MiPcJob.Runspace.Dispose(); $script:MiPcJob.Dispose(); $script:MiPcJob = $null }
    $script:MiPc = $m.D
    $ui.PcEstado.Text = ''
    $ui.PcLista.Children.Clear()
    foreach ($x in $script:MiPc) {
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = New-Object Windows.CornerRadius 10; $b.Padding = New-Object Windows.Thickness 12, 8, 12, 8
        $b.Margin = New-Object Windows.Thickness 0, 0, 0, 8
        $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
        $sp = New-Object Windows.Controls.StackPanel
        foreach ($l in @(@($x.T.ToUpper(), 10, 'Bold', 'Muted'), @($x.V, 13, 'Normal', 'Text'), @($x.S, 11, 'Normal', 'Muted'))) {
            if (-not $l[0]) { continue }
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = $l[0]; $tb.FontSize = $l[1]; $tb.FontWeight = $l[2]; $tb.TextWrapping = 'Wrap'
            $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $l[3])
            [void]$sp.Children.Add($tb)
        }
        $b.Child = $sp
        [void]$ui.PcLista.Children.Add($b)
    }
}

# ---------- puntaje de la Revisión completa + asistente de la primera vez ----------
function Set-PuntajeUI {
    $ui.DiagSub.Text = if ($null -ne $cfg.UltPuntaje) { "Último puntaje: $($cfg.UltPuntaje)/100 · $($cfg.UltEtiqueta)" } else { 'Puntaje y qué mejorar' }
    # el número grande arriba a la derecha de la tarjeta (con 3 columnas la línea de abajo no entra)
    if ($null -ne $cfg.UltPuntaje) {
        $p = [int]$cfg.UltPuntaje
        $ui.DiagPuntaje.Text = "$p"
        $ui.DiagPuntaje.Foreground = if ($p -ge 75) { $Colores.ok } elseif ($p -ge 55) { $Colores.warn } else { $Colores.err }
        $ui.DiagPuntaje.ToolTip = "Última revisión: $p/100 · $($cfg.UltEtiqueta)"
    } else { $ui.DiagPuntaje.Text = '' }
}
function Handle-Puntaje($m) {
    $cfg.UltPuntaje = $m.P; $cfg.UltEtiqueta = $m.E; Save-Cfg
    Set-PuntajeUI
    if ($script:AsistenteEnCurso) { $script:AsistentePuntaje = $m }   # el resumen se muestra cuando termina la revisión
}

# Primera vez que se abre: ofrece revisar la PC y, al terminar, arreglar solo lo que se puede arreglar solo
function Start-Asistente {
    $cfg.AsistenteVisto = $true; Save-Cfg
    $ok = Show-Dialogo '¡Hola! ¿Revisamos tu PC?' "Tarda unos segundos: miro la RAM, los discos, la placa de video, la red y los pantallazos, te doy un puntaje de 0 a 100 y te digo qué conviene mejorar.`n`nNo cambia nada sin preguntarte." 'Revisar' 'Más tarde' 'pregunta'
    if (-not $ok) { return }
    $script:AsistenteEnCurso = $true
    Start-Accion 'diagnostico'
}
function Show-ResumenAsistente {
    $script:AsistenteEnCurso = $false
    $m = $script:AsistentePuntaje; $script:AsistentePuntaje = $null
    if (-not $m) { return }
    $txt = "Tu PC sacó $($m.P) de 100 ($($m.E)).`n`n"
    $txt += if ($m.N) { "En Actividad (a la derecha) está la lista de qué mejorar, de lo más importante a lo menos." } else { 'No hay nada importante para mejorar.' }
    if (@($m.Auto).Count) {
        $txt += "`n`nEsto lo puedo arreglar yo ahora mismo:`n" + ((@($m.Auto) | ForEach-Object { "•  $_" }) -join "`n") + "`n`n(Es lo mismo que el botón Todo para jugar: todo vuelve a como estaba con Restaurar ajustes.)"
        if (Show-Dialogo "Puntaje: $($m.P)/100" $txt 'Arreglarlo' 'Ahora no' 'info') { Start-Accion 'todo' }
    } else {
        Show-Dialogo "Puntaje: $($m.P)/100" $txt 'Entendido' '' 'info' | Out-Null
    }
}

# resumen para pegar en Discord (con negritas de Discord)
$ui.PcCopiar.Add_MouseLeftButtonUp({
    if (-not $script:MiPc) { return }
    $lineas = @('**Mi PC** (Optimizador J.vps)') + @($script:MiPc | ForEach-Object { "**$($_.T):** $($_.V)" + $(if ($_.S) { " — $($_.S)" }) })
    try { [Windows.Clipboard]::SetText($lineas -join "`r`n"); $ui.PcEstado.Text = 'Copiado: pegalo en Discord' }
    catch { $ui.PcEstado.Text = 'No se pudo copiar' }
})

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
        @{ T = 'toggle'; Texto = 'Iniciar con Windows'; On = (Test-Inicio); A = { Toggle-Inicio } }
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
# INSTALADOR (asistente de instalación)
# ================================
# Reemplaza al cartel "¿Abrir siempre sin pedir permisos?": un asistente de 4 pasos como el de cualquier
# programa (Bienvenida, Opciones, Instalando, Listo) con los colores del tema actual.
# Show-Instalador devuelve $true si quedó instalado.

[xml]$instXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instalar Optimizador J.vps" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize" ShowInTaskbar="True" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Pri" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryFg}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MinWidth" Value="104"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="{DynamicResource Grad}" Padding="20,9">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Sec" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MinWidth" Value="90"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="Transparent" BorderBrush="{DynamicResource Line}" BorderThickness="1" Padding="18,8">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Cerrar" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Width="46" Height="36" CornerRadius="0,12,0,0" Background="Transparent">
              <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{TemplateBinding Foreground}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#C42B1C"/><Setter Property="Foreground" Value="White"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.3"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Chk" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border x:Name="caja" Width="18" Height="18" CornerRadius="5" BorderThickness="1.5" BorderBrush="{DynamicResource Muted}" Background="Transparent" VerticalAlignment="Top" Margin="0,1,12,0">
                <TextBlock x:Name="tilde" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="{DynamicResource PrimaryFg}" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="caja" Property="Background" Value="{DynamicResource Grad}"/>
                <Setter TargetName="caja" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="tilde" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Titulo" TargetType="TextBlock">
      <Setter Property="FontSize" Value="24"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    </Style>
    <Style x:Key="Bajada" TargetType="TextBlock">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="LineHeight" Value="21"/>
      <Setter Property="Margin" Value="0,8,0,0"/>
    </Style>
    <Style x:Key="Punto" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
  </Window.Resources>
  <Border x:Name="Caja" Margin="18" CornerRadius="12" Background="{DynamicResource DlgBg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" ClipToBounds="True">
    <Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="6" Opacity="0.5" Color="Black"/></Border.Effect>
    <Grid Width="760" Height="500">
      <Grid.RowDefinitions><RowDefinition Height="36"/><RowDefinition Height="*"/></Grid.RowDefinitions>

      <!-- barra de título -->
      <Border x:Name="Barra" Background="{DynamicResource LogBg}" BorderBrush="{DynamicResource Line}" BorderThickness="0,0,0,1" CornerRadius="12,12,0,0">
        <Grid>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
            <Ellipse x:Name="LogoChico" Width="18" Height="18" Margin="0,0,10,0"/>
            <TextBlock Text="Instalar Optimizador J.vps" FontSize="12" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
          </StackPanel>
          <Button x:Name="BtnX" Style="{StaticResource Cerrar}" HorizontalAlignment="Right" ToolTip="Cerrar"/>
        </Grid>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

        <!-- costado: logo y pasos -->
        <Border Background="{DynamicResource LogBg}" BorderBrush="{DynamicResource Line}" BorderThickness="0,0,1,0" CornerRadius="0,0,0,12" ClipToBounds="True">
          <Grid>
            <Ellipse Width="230" Height="230" Margin="-80,-80,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Fill="{DynamicResource Accent}" Opacity="0.10">
              <Ellipse.Effect><BlurEffect Radius="60"/></Ellipse.Effect>
            </Ellipse>
            <DockPanel Margin="22,26,22,20">
              <StackPanel DockPanel.Dock="Top">
                <Border Width="64" Height="64" CornerRadius="32" Background="{DynamicResource Grad}" Padding="3" HorizontalAlignment="Left">
                  <Ellipse x:Name="LogoGrande" Stroke="{DynamicResource LogBg}" StrokeThickness="2"/>
                </Border>
                <TextBlock Text="Optimizador J.vps" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource Text}" Margin="0,12,0,0"/>
                <TextBlock x:Name="Ver" FontSize="12" Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>
              </StackPanel>
              <TextBlock DockPanel.Dock="Bottom" Text="Hecho por J.vps" FontSize="11" Foreground="{DynamicResource Muted}"/>
              <StackPanel x:Name="Pasos" Margin="0,26,0,0"/>
            </DockPanel>
          </Grid>
        </Border>

        <!-- contenido -->
        <Grid Grid.Column="1">
          <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <Grid Margin="36,30,36,0">

            <!-- 1. Bienvenida -->
            <StackPanel x:Name="P0">
              <TextBlock Style="{StaticResource Titulo}" Text="Te damos la bienvenida"/>
              <TextBlock Style="{StaticResource Bajada}" Text="Este asistente instala el Optimizador J.vps en tu PC: limpieza, modo juego, red con menos picos y datos en pantalla mientras jugás."/>
              <Border Background="{DynamicResource Bg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="10" Padding="18,14,18,6" Margin="0,20,0,0">
                <StackPanel>
                  <TextBlock Text="AL INSTALARLO" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Muted}" Margin="0,0,0,12"/>
                  <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" Margin="0,2,10,0"/><TextBlock Style="{StaticResource Punto}" Text="Se abre sin pedir permisos de administrador cada vez"/></StackPanel>
                  <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" Margin="0,2,10,0"/><TextBlock Style="{StaticResource Punto}" Text="Se actualiza solo cuando sale una versión nueva"/></StackPanel>
                  <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource Accent}" Margin="0,2,10,0"/><TextBlock Style="{StaticResource Punto}" Text="No borra archivos personales y todo se puede deshacer"/></StackPanel>
                </StackPanel>
              </Border>
            </StackPanel>

            <!-- 2. Opciones -->
            <StackPanel x:Name="P1" Visibility="Collapsed">
              <TextBlock Style="{StaticResource Titulo}" Text="Opciones de instalación"/>
              <TextBlock Style="{StaticResource Bajada}" Text="Elegí cómo querés tenerlo a mano."/>
              <TextBlock Text="Carpeta" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource Muted}" Margin="0,18,0,6"/>
              <DockPanel>
                <Button x:Name="BtnCarpeta" Style="{StaticResource Sec}" Content="Cambiar…" DockPanel.Dock="Right" Margin="8,0,0,0" MinWidth="0"/>
                <Border Background="{DynamicResource Bg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="8" Padding="12,9">
                  <DockPanel>
                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource Muted}" DockPanel.Dock="Right" VerticalAlignment="Center" ToolTip="Carpeta protegida: solo un administrador puede modificarla"/>
                    <TextBlock x:Name="Carpeta" FontSize="13" Foreground="{DynamicResource Text}" TextTrimming="CharacterEllipsis"/>
                  </DockPanel>
                </Border>
              </DockPanel>
              <TextBlock x:Name="NotaCarpeta" Text="Podés ponerlo en otro disco. Siempre queda protegido: solo un administrador lo puede modificar." FontSize="12" Foreground="{DynamicResource Muted}" Margin="0,6,0,0" TextWrapping="Wrap"/>
              <Border Background="{DynamicResource Bg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="10" Padding="16,4" Margin="0,16,0,0">
                <StackPanel>
                  <CheckBox x:Name="ChkEscritorio" Style="{StaticResource Chk}" IsChecked="True" Padding="0" Margin="0,10"><TextBlock Text="Crear acceso directo en el escritorio"/></CheckBox>
                  <Border Height="1" Background="{DynamicResource Line}"/>
                  <CheckBox x:Name="ChkInicio" Style="{StaticResource Chk}" Margin="0,10">
                    <StackPanel>
                      <TextBlock Text="Iniciar con Windows"/>
                      <TextBlock Text="Queda en la bandeja, al lado del reloj" FontSize="12" Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>
                    </StackPanel>
                  </CheckBox>
                  <Border Height="1" Background="{DynamicResource Line}"/>
                  <CheckBox x:Name="ChkMenu" Style="{StaticResource Chk}" IsChecked="True" Margin="0,10"><TextBlock Text="Agregar al menú Inicio"/></CheckBox>
                </StackPanel>
              </Border>
            </StackPanel>

            <!-- 3. Instalando -->
            <StackPanel x:Name="P2" Visibility="Collapsed">
              <TextBlock x:Name="TitInst" Style="{StaticResource Titulo}" Text="Instalando…"/>
              <TextBlock x:Name="SubInst" Style="{StaticResource Bajada}" Text="Esto tarda unos segundos."/>
              <DockPanel Margin="0,22,0,8">
                <TextBlock x:Name="Pct" DockPanel.Dock="Right" FontSize="13" Foreground="{DynamicResource Muted}"/>
                <TextBlock x:Name="Tarea" FontSize="13" Foreground="{DynamicResource Text}" TextTrimming="CharacterEllipsis"/>
              </DockPanel>
              <Border x:Name="Pista" Height="8" CornerRadius="4" Background="{DynamicResource Line}" ClipToBounds="True">
                <Border x:Name="Barrita" Width="0" HorizontalAlignment="Left" CornerRadius="4" Background="{DynamicResource Grad}"/>
              </Border>
              <Border Background="{DynamicResource LogBg}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="10" Padding="14,12" Margin="0,18,0,0" MinHeight="130">
                <StackPanel x:Name="Registro"/>
              </Border>
            </StackPanel>

            <!-- 4. Listo -->
            <StackPanel x:Name="P3" Visibility="Collapsed" Margin="0,18,0,0">
              <Border Width="56" Height="56" CornerRadius="28" Background="{DynamicResource Grad}" HorizontalAlignment="Left">
                <TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="24" Foreground="{DynamicResource PrimaryFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Style="{StaticResource Titulo}" Text="¡Listo! Ya está instalado" Margin="0,18,0,0"/>
              <TextBlock x:Name="TextoListo" Style="{StaticResource Bajada}"/>
            </StackPanel>
          </Grid>

          <!-- botones -->
          <Border Grid.Row="1" BorderBrush="{DynamicResource Line}" BorderThickness="0,1,0,0" Padding="36,16,36,20" Margin="0,16,0,0">
            <DockPanel>
              <Button x:Name="BtnCancelar" Style="{StaticResource Sec}" Content="Cancelar" DockPanel.Dock="Left"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="BtnAtras" Style="{StaticResource Sec}" Content="Atrás" Margin="0,0,10,0" Visibility="Collapsed"/>
                <Button x:Name="BtnSig" Style="{StaticResource Pri}" Content="Siguiente" IsDefault="True"/>
              </StackPanel>
            </DockPanel>
          </Border>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

function Show-Instalador([bool]$conInicio = $false) {
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $instXaml))
    $I = @{}
    foreach ($n in 'Caja', 'Barra', 'LogoChico', 'LogoGrande', 'BtnX', 'Ver', 'Pasos', 'P0', 'P1', 'P2', 'P3', 'Carpeta', 'ChkEscritorio', 'ChkInicio', 'ChkMenu',
                   'BtnCarpeta', 'NotaCarpeta', 'TitInst', 'SubInst', 'Pct', 'Tarea', 'Pista', 'Barrita', 'Registro', 'TextoListo', 'BtnCancelar', 'BtnAtras', 'BtnSig') { $I[$n] = $w.FindName($n) }
    $I.Ver.Text = "Versión $Version"
    $I.ChkInicio.IsChecked = $conInicio
    if ($logo) {
        foreach ($el in $I.LogoChico, $I.LogoGrande) { $b = New-Object Windows.Media.ImageBrush $logo; $b.Stretch = 'UniformToFill'; $el.Fill = $b }
        $w.Icon = $logo
    }
    $script:Inst = @{ W = $w; I = $I; Paso = 0; Ok = $false; Corriendo = $false; Timer = $null; Carpeta = $InstDirDefecto }
    $I.Carpeta.Text = $InstDirDefecto
    # un Optimizador.exe compilado antes de esto solo sabe abrir la copia de Archivos de programa
    if ($Exe -and [int]$env:OptimizadorLanzador -lt 2) { $I.BtnCarpeta.Visibility = 'Collapsed'; $I.NotaCarpeta.Text = 'Se instala en Archivos de programa: ahí ningún otro programa lo puede modificar.' }

    # pasos del costado: un círculo con el número (o la tilde) y el nombre
    $script:Inst.Filas = foreach ($nombre in 'Bienvenida', 'Opciones', 'Instalando', 'Listo') {
        $fila = New-Object Windows.Controls.Border
        $fila.CornerRadius = 8; $fila.Padding = '10,8'; $fila.Margin = '0,0,0,4'
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $circ = New-Object Windows.Controls.Border; $circ.Width = 24; $circ.Height = 24; $circ.CornerRadius = 12; $circ.Margin = '0,0,12,0'
        $num = New-Object Windows.Controls.TextBlock; $num.FontSize = 12; $num.FontWeight = 'Bold'; $num.HorizontalAlignment = 'Center'; $num.VerticalAlignment = 'Center'
        $circ.Child = $num
        $txt = New-Object Windows.Controls.TextBlock; $txt.Text = $nombre; $txt.FontSize = 13; $txt.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($circ); [void]$sp.Children.Add($txt); $fila.Child = $sp
        [void]$I.Pasos.Children.Add($fila)
        @{ Fila = $fila; Circ = $circ; Num = $num; Txt = $txt }
    }

    $w.Owner = $(if ($win -and $win.IsVisible) { $win } else { $null })
    $w.WindowStartupLocation = if ($w.Owner) { 'CenterOwner' } else { 'CenterScreen' }
    $I.Barra.Add_MouseLeftButtonDown({ $script:Inst.W.DragMove() })
    $cancelar = { if (-not $script:Inst.Corriendo) { $script:Inst.W.Close() } }
    $I.BtnX.Add_Click($cancelar)
    $I.BtnCancelar.Add_Click($cancelar)
    $I.BtnAtras.Add_Click({ Set-PasoInstalador 0 })
    $I.BtnCarpeta.Add_Click({ Select-CarpetaInstalador })
    $I.BtnSig.Add_Click({
        switch ($script:Inst.Paso) {
            0 { Set-PasoInstalador 1 }
            1 { Start-Instalacion }
            3 { $script:Inst.W.Close() }
        }
    })
    $w.Add_KeyDown({ if ($_.Key -eq 'Escape' -and -not $script:Inst.Corriendo) { $this.Close() } })
    # no se puede cerrar a mitad de la instalación (Alt+F4 incluido)
    $w.Add_Closing({ if ($script:Inst.Corriendo) { $_.Cancel = $true } })
    Set-PasoInstalador 0
    [void]$w.ShowDialog()
    $script:Inst.Ok
}

# elegir carpeta: se acepta Archivos de programa o la raíz de un disco (ver Resolve-CarpetaInstalacion)
function Select-CarpetaInstalador {
    $s = $script:Inst; $I = $s.I
    Add-Type -AssemblyName System.Windows.Forms
    $fb = New-Object Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Elegí dónde instalar el Optimizador (se crea la carpeta "Optimizador J.vps" adentro)'
    $fb.SelectedPath = Split-Path $s.Carpeta
    if ($fb.ShowDialog() -ne 'OK') { return }
    $final = Resolve-CarpetaInstalacion $fb.SelectedPath
    if ($final) {
        $s.Carpeta = $final
        $I.Carpeta.Text = $final
        $I.NotaCarpeta.Text = 'Podés ponerlo en otro disco. Siempre queda protegido: solo un administrador lo puede modificar.'
        $I.NotaCarpeta.Foreground = $Colores.muted
    } else {
        $I.NotaCarpeta.Text = "Ahí no: adentro de otra carpeta cualquier programa podría reemplazarlo. Elegí un disco (por ejemplo D:\) o Archivos de programa."
        $I.NotaCarpeta.Foreground = $Colores.warn
    }
}

function Set-PasoInstalador([int]$paso) {
    $s = $script:Inst; $I = $s.I
    $s.Paso = $paso
    # ojo: en PowerShell $i y $I son la misma variable (por eso el contador se llama $k)
    for ($k = 0; $k -lt 4; $k++) {
        $I["P$k"].Visibility = if ($k -eq $paso) { 'Visible' } else { 'Collapsed' }
        $f = $s.Filas[$k]
        $hecho = $k -lt $paso; $actual = $k -eq $paso
        $f.Num.Text = if ($hecho) { [char]0xE73E } else { [string]($k + 1) }
        $f.Num.FontFamily = if ($hecho) { 'Segoe MDL2 Assets' } else { 'Segoe UI' }
        if ($hecho) {
            $f.Circ.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Grad'); $f.Circ.BorderThickness = 0
            $f.Num.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'PrimaryFg')
        } else {
            $f.Circ.Background = [Windows.Media.Brushes]::Transparent
            $f.Circ.BorderThickness = $(if ($actual) { 2 } else { 1.5 })
            $f.Circ.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($actual) { 'Accent' } else { 'Muted' }))
            $f.Num.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($actual) { 'Text' } else { 'Muted' }))
        }
        $f.Txt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($hecho -or $actual) { 'Text' } else { 'Muted' }))
        $f.Txt.FontWeight = if ($actual) { 'SemiBold' } else { 'Normal' }
        if ($actual) { $f.Fila.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Hover') } else { $f.Fila.Background = [Windows.Media.Brushes]::Transparent }
    }
    $I.BtnAtras.Visibility = if ($paso -eq 1) { 'Visible' } else { 'Collapsed' }
    $I.BtnCancelar.Visibility = if ($paso -lt 2) { 'Visible' } else { 'Hidden' }
    $I.BtnSig.Visibility = if ($paso -eq 2) { 'Hidden' } else { 'Visible' }
    $I.BtnSig.Content = switch ($paso) { 0 { 'Siguiente' } 1 { 'Instalar' } default { 'Finalizar' } }
}

function Add-LineaInstalador([string]$texto, [string]$tipo) {
    $t = New-Object Windows.Controls.TextBlock
    $t.FontFamily = 'Consolas'; $t.FontSize = 12; $t.Margin = '0,0,0,6'; $t.TextWrapping = 'Wrap'
    $marca = @{ hecho = '✓ '; actual = '› '; error = '✗ ' }[$tipo]
    $t.Text = $marca + $texto
    $t.Foreground = switch ($tipo) { 'hecho' { $Colores.ok } 'error' { $Colores.err } default { $Colores.info } }
    [void]$script:Inst.I.Registro.Children.Add($t)
    $t
}

function Set-ProgresoInstalador([int]$pct) {
    $I = $script:Inst.I
    $I.Pct.Text = "$pct %"
    $anim = New-Object Windows.Media.Animation.DoubleAnimation
    $anim.To = $I.Pista.ActualWidth * $pct / 100
    $anim.Duration = [TimeSpan]::FromMilliseconds(300)
    $anim.EasingFunction = New-Object Windows.Media.Animation.QuadraticEase
    $I.Barrita.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $anim)
}

# Cada paso corre en el hilo de la ventana (son cosas cortas) y entre uno y otro se deja respirar a la
# interfaz, así la barra y la lista se ven avanzar en vez de quedar congelado hasta el final.
function Start-Instalacion {
    $s = $script:Inst; $I = $s.I
    $escritorio = [bool]$I.ChkEscritorio.IsChecked
    $menu = [bool]$I.ChkMenu.IsChecked
    $inicio = [bool]$I.ChkInicio.IsChecked
    Set-CarpetaInstalacion $s.Carpeta
    $I.BtnCarpeta.IsEnabled = $false
    $s.Pasos = @(
        @{ T = 'Copiando el programa a Archivos de programa'; P = 25; F = { Install-Archivos } },
        @{ T = 'Creando la tarea para abrir sin permisos'; P = 45; F = { Install-Tarea } }
    )
    if ($escritorio) { $s.Pasos += @{ T = 'Creando el acceso directo en el escritorio'; P = 60; F = { Set-AccesoDirecto (Get-LnkEscritorio) } } }
    if ($menu) { $s.Pasos += @{ T = 'Agregando al menú Inicio'; P = 70; F = { Set-AccesoDirecto (Get-LnkMenu) } } }
    $s.Pasos += @{ T = $(if ($inicio) { 'Configurando el inicio con Windows' } else { 'Revisando el inicio con Windows' }); P = 85; F = $(if ($inicio) { { Set-Inicio $true } } else { { if (Test-Inicio) { Set-Inicio $true } } }) }
    $s.Pasos += @{ T = 'Registrando en Aplicaciones instaladas'; P = 100; F = { Register-Desinstalador } }
    $s.Indice = 0; $s.Linea = $null
    $s.Corriendo = $true
    $I.BtnX.IsEnabled = $false
    Set-PasoInstalador 2
    $I.Registro.Children.Clear()
    $I.Pct.Text = '0 %'

    $s.Timer = New-Object Windows.Threading.DispatcherTimer
    $s.Timer.Interval = [TimeSpan]::FromMilliseconds(380)
    $s.Timer.Add_Tick({
        $s = $script:Inst; $I = $s.I
        if ($s.Linea) { $s.Linea.Text = '✓ ' + $s.Pasos[$s.Indice - 1].T; $s.Linea.Foreground = $Colores.ok; $s.Linea = $null }
        if ($s.Indice -ge $s.Pasos.Count) { $s.Timer.Stop(); Stop-Instalacion $true; return }
        $p = $s.Pasos[$s.Indice]
        $I.Tarea.Text = $p.T + '…'
        $linea = Add-LineaInstalador $p.T 'actual'
        # se dibuja la línea nueva antes de hacer el paso (que puede tardar un segundo)
        $I.Registro.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Render)
        try {
            & $p.F
        } catch {
            $s.Timer.Stop()
            $linea.Text = '✗ ' + $p.T; $linea.Foreground = $Colores.err
            [void](Add-LineaInstalador $_.Exception.Message 'error')
            Stop-Instalacion $false
            return
        }
        $s.Linea = $linea
        Set-ProgresoInstalador $p.P
        $s.Indice++
    })
    $s.Timer.Start()
}

function Stop-Instalacion([bool]$ok) {
    $s = $script:Inst; $I = $s.I
    $s.Corriendo = $false
    $I.BtnX.IsEnabled = $true
    if ($ok) {
        $s.Ok = $true
        $donde = @()
        if ($I.ChkEscritorio.IsChecked) { $donde += 'el escritorio' }
        if ($I.ChkMenu.IsChecked) { $donde += 'el menú Inicio' }
        $I.TextoListo.Text = $(if ($donde) { "Lo encontrás en $($donde -join ' y '). " } else { '' }) +
            'Desde ahí abre directo, sin el aviso de Windows. Al cerrar la ventana queda en la bandeja, al lado del reloj (la paloma).'
        Set-PasoInstalador 3
    } else {
        $I.TitInst.Text = 'No se pudo instalar'
        $I.SubInst.Text = 'No se cambió nada importante: el Optimizador sigue funcionando igual. Probá abrirlo con permisos de administrador.'
        $I.Tarea.Text = ''
        $I.BtnSig.Content = 'Cerrar'; $I.BtnSig.Visibility = 'Visible'
        $s.Paso = 3   # el botón cierra
    }
}
# ================================
# MENU (oscuro y redondeado, para la bandeja y el overlay)
# ================================

[xml]$menuXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="False" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize" FontFamily="Segoe UI">
  <!-- como la ventana principal: esquinas, sombra, borde y desenfoque (Vidrio) los pone Windows -->
  <WindowChrome.WindowChrome>
    <WindowChrome GlassFrameThickness="-1" CaptionHeight="0" ResizeBorderThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Border x:Name="MBox" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="{DynamicResource MenuBg}" Padding="5">
    <StackPanel x:Name="MItems" MinWidth="220"/>
  </Border>
</Window>
'@
$menuWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $menuXaml))
Set-VentanaHerramienta $menuWin $false
$mBox = $menuWin.FindName('MBox'); $mItems = $menuWin.FindName('MItems')
# Set-VentanaHerramienta ya creó la ventana de Windows: el estilo se aplica cuando se elige el tema (Set-Tema)
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
    # el texto puede venir ya armado (ej. la fila de un disco con su barra)
    if ($texto -is [Windows.UIElement]) { [void]$g.Children.Add($texto) }
    else {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $texto; $tb.FontSize = 13; $tb.Foreground = $Colores.text; $tb.VerticalAlignment = 'Center'
        [void]$g.Children.Add($tb)
    }
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
    # límites del monitor donde está el mouse (no el principal)
    $w = $menuWin.ActualWidth; $h = $menuWin.ActualHeight; $wa = Get-AreaMonitor ([Windows.Forms.Screen]::FromPoint($px))
    $x = $pt.X - $w; $y = $pt.Y - $h
    if ($x -lt $wa.Left) { $x = $pt.X }
    if ($y -lt $wa.Top) { $y = $pt.Y }
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
    if (-not $script:Actualizando -and -not $Captura -and (Test-Path -LiteralPath (Join-Path $Raiz 'juego_respaldo.json'))) {
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
    # y por este se cierra: lo usa Optimizador.exe cuando se reemplaza por uno nuevo (Optimizador.exe.nuevo)
    $script:EvtSalir = New-Object Threading.EventWaitHandle $false, ([Threading.EventResetMode]::AutoReset), 'Local\OptimizadorJvps_Salir', ([ref]$nuevo), $sec
}

# ---------- router ----------
# Cada 3 s le hace ping al router y a internet (en segundo plano, sin trabar la ventana). Si el router es un
# Movistar Fibra aparece la fila "Router" con el botón para reiniciarlo. Si el router deja de contestar más de
# 25 s avisa con un globo (una vez por corte) y cada corte queda anotado en el registro del día.
$ArchRouter = Join-Path $Raiz 'router.bin'
# la contraseña que ya se guardó en la app "Reiniciar Router" (mismo cifrado): no la pide de nuevo
$ClaveAppRouter = Join-Path $env:LOCALAPPDATA 'Reiniciar Router\clave.bin'
if (-not $Captura -and -not (Test-Path -LiteralPath $ArchRouter) -and (Test-Path -LiteralPath $ClaveAppRouter)) {
    try { Copy-Item -LiteralPath $ClaveAppRouter -Destination $ArchRouter } catch { }
}
$script:Rt = @{ Ip = $null; IpVisto = [datetime]::MinValue; Compat = $null; Detect = $null; Intentos = 0; DetectFallo = [datetime]::MinValue
                PingR = $null; PingI = $null; Tick = 0; Ok = $null; Ms = -1; Visto = $false; CaidoDesde = $null; Avisado = $false
                Cortes = 0; Dia = (Get-Date).Date }

function Test-ReinicioRouter {
    ($script:Job -and $script:AccionActual -eq 'router') -or ($script:RouterReinicioHasta -and (Get-Date) -lt $script:RouterReinicioHasta)
}

function Write-LogDia([string]$texto) {
    try {
        $dir = Join-Path $Raiz 'logs'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Add-Content -Path (Join-Path $dir ("optimizador_{0:yyyy-MM-dd}.log" -f (Get-Date))) -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $texto) -Encoding UTF8
    } catch { }
}

function Format-Seg([int]$s) { if ($s -lt 60) { "$s segundos" } else { '{0}:{1:00} minutos' -f [int][math]::Floor($s / 60), ($s % 60) } }

function Check-Router {
    $rt = $script:Rt
    # cambió de red (otra puerta de enlace): empieza de cero
    if (((Get-Date) - $rt.IpVisto).TotalSeconds -ge 30) {
        $rt.IpVisto = Get-Date
        $ip = [JVps.Router]::Puerta()
        if ($ip -ne $rt.Ip) {
            $rt.Ip = $ip; $rt.Compat = $null; $rt.Detect = $null; $rt.Intentos = 0; $rt.Visto = $false; $rt.CaidoDesde = $null; $rt.Avisado = $false; $rt.Ok = $null
            Set-RouterUI
        }
    }
    if (-not $rt.Ip) { return }
    # ¿es un Movistar Fibra? Se mira la página de inicio del router una vez por red
    if ($rt.Detect -and $rt.Detect.IsCompleted) {
        if ($rt.Detect.Status -eq 'RanToCompletion') { $rt.Compat = [JVps.Router]::Compatible($rt.Detect.Result) }
        elseif (++$rt.Intentos -ge 3) { $rt.Compat = $false }   # no tiene página o no es este modelo
        else { $rt.DetectFallo = Get-Date }
        $rt.Detect = $null
        Set-RouterUI
    }
    if ($null -eq $rt.Compat -and -not $rt.Detect -and ((Get-Date) - $rt.DetectFallo).TotalSeconds -ge 60) {
        $wc = New-Object Net.WebClient; $wc.Proxy = $null; $wc.Encoding = [Text.Encoding]::UTF8
        $rt.Detect = $wc.DownloadStringTaskAsync("http://$($rt.Ip)/")
    }
    # sin sesión de Discord no lo vigila (ni pings ni avisos): la fila queda con el candado
    if (-not $cfg.Discord.Id) {
        if ($null -ne $rt.Ok) { $rt.Ok = $null; $rt.Visto = $false; $rt.CaidoDesde = $null; $rt.Avisado = $false; $rt.PingR = $null; $rt.PingI = $null; Set-RouterUI }
        return
    }
    # pings: se mandan cada 3 s y se leen cuando terminan
    if ($rt.PingR) {
        if (-not ($rt.PingR.IsCompleted -and $rt.PingI.IsCompleted)) { return }
        $okR = $rt.PingR.Status -eq 'RanToCompletion' -and $rt.PingR.Result.Status -eq 'Success'
        $ms = if ($rt.PingI.Status -eq 'RanToCompletion' -and $rt.PingI.Result.Status -eq 'Success') { [int]$rt.PingI.Result.RoundtripTime } else { -1 }
        $rt.PingR = $null; $rt.PingI = $null
        Set-PingRouter $okR $ms
    }
    if ((++$rt.Tick % 3) -ne 0) { return }
    $rt.PingR = (New-Object Net.NetworkInformation.Ping).SendPingAsync($rt.Ip, 1000)
    $rt.PingI = (New-Object Net.NetworkInformation.Ping).SendPingAsync('8.8.8.8', 1500)
}

function Set-PingRouter([bool]$okR, [int]$ms) {
    $rt = $script:Rt
    if ((Get-Date).Date -ne $rt.Dia) { $rt.Dia = (Get-Date).Date; $rt.Cortes = 0 }
    $rt.Ok = $okR; $rt.Ms = $ms
    if ($okR) {
        if ($rt.CaidoDesde) {
            $seg = [int]((Get-Date) - $rt.CaidoDesde).TotalSeconds
            if ($seg -ge 10 -and -not (Test-ReinicioRouter)) { $rt.Cortes++; Write-LogDia "Red: el router no contestó durante $seg s" }
            if ($rt.Avisado -and -not $Captura) { $tray.ShowBalloonTip(4000, 'Volvió la conexión', "El router estuvo sin contestar $(Format-Seg $seg).", 'Info') }
        }
        $rt.Visto = $true; $rt.CaidoDesde = $null; $rt.Avisado = $false
    }
    # solo si alguna vez contestó: hay routers que no responden pings
    elseif ($rt.Visto -and -not (Test-ReinicioRouter)) {
        if (-not $rt.CaidoDesde) { $rt.CaidoDesde = Get-Date }
        elseif (-not $rt.Avisado -and ((Get-Date) - $rt.CaidoDesde).TotalSeconds -ge 25 -and -not $Captura) {
            $rt.Avisado = $true
            $txt = if ($rt.Compat) { 'Hace 25 segundos que no contesta. Si no vuelve solo, tocá acá para reiniciarlo.' }
                   else { 'Hace 25 segundos que no contesta. Si no vuelve solo, desenchufalo 30 segundos y volvelo a enchufar.' }
            $script:GloboRouter = Get-Date
            $tray.ShowBalloonTip(6000, 'Tu router dejó de responder', $txt, 'Warning')
        }
    }
    Set-RouterUI
}

function Set-RouterUI {
    $rt = $script:Rt
    $ui.RouterFila.Visibility = if ($rt.Compat) { 'Visible' } else { 'Collapsed' }
    if (-not $rt.Compat) { return }
    if (-not $cfg.Discord.Id) {
        $ui.RouterClaveLink.Visibility = 'Collapsed'; $ui.BtnRouter.Content = 'Iniciar sesión'
        $ui.RouterSub.Text = 'Movistar Fibra · iniciá sesión con Discord para usarlo'; $ui.RouterPunto.Fill = $Colores.muted
        return
    }
    $ui.BtnRouter.Content = 'Reiniciar'
    $ui.RouterClaveLink.Visibility = if (Test-Path -LiteralPath $ArchRouter) { 'Visible' } else { 'Collapsed' }
    $cortes = if ($rt.Cortes -eq 1) { ' · se cortó 1 vez hoy' } elseif ($rt.Cortes -gt 1) { " · se cortó $($rt.Cortes) veces hoy" } else { '' }
    if (Test-ReinicioRouter) { $c = $Colores.warn; $t = 'reiniciando...' }
    elseif ($null -eq $rt.Ok) { $c = $Colores.muted; $t = 'midiendo...' }
    elseif (-not $rt.Ok) { $c = $Colores.err; $t = $(if ($rt.CaidoDesde) { "no contesta hace $([int]((Get-Date) - $rt.CaidoDesde).TotalSeconds) s" } else { 'no contesta' }) }
    elseif ($rt.Ms -lt 0) { $c = $Colores.err; $t = 'el router anda, pero no hay internet' }
    elseif ($rt.Ms -gt 150) { $c = $Colores.warn; $t = "internet lento · $($rt.Ms) ms" }
    else { $c = $Colores.ok; $t = "internet anda bien · $($rt.Ms) ms" }
    $ui.RouterSub.Text = "Movistar Fibra · $t$cortes"
    $ui.RouterPunto.Fill = $c
}

# pide la contraseña de la etiqueta y la guarda cifrada (DPAPI: solo este usuario de Windows la puede leer)
function Show-ClaveRouter {
    $d = New-Dialogo 'Contraseña del router' "Está en la etiqueta de abajo del router, donde dice `"Datos de acceso al Router`" (no es la del Wi-Fi).`n`nSe guarda cifrada en esta PC, solo para tu usuario de Windows." 'Guardar' 'Cancelar' 'escudo'
    $pb = New-Object Windows.Controls.PasswordBox
    $pb.Margin = '0,16,0,0'; $pb.Padding = '10,7'; $pb.FontSize = 14; $pb.MaxLength = 64; $pb.BorderThickness = 1
    $pb.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'LogBg')
    $pb.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $pb.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line')
    $pb.SetResourceReference([Windows.Controls.PasswordBox]::CaretBrushProperty, 'Text')
    $d.FindName('DTexto').Parent.Parent.Children.Insert(2, $pb)
    $d.Tag = $pb
    $d.Add_ContentRendered({ [void]$this.Tag.Focus() })
    if (-not $d.ShowDialog()) { return $false }
    $clave = $pb.Password
    if (-not $clave) { return $false }
    Add-Type -AssemblyName System.Security
    if (-not (Test-Path $Raiz)) { New-Item -ItemType Directory -Path $Raiz | Out-Null }
    [IO.File]::WriteAllBytes($ArchRouter, [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($clave), $null, 'CurrentUser'))
    Set-RouterUI
    $true
}

function Start-ReiniciarRouter {
    if ($script:Job) { return }
    if (-not $cfg.Discord.Id) { Request-Discord 'ver y reiniciar el router desde el Optimizador' { Set-RouterUI }; return }
    if (-not (Test-Path -LiteralPath $ArchRouter) -and -not (Show-ClaveRouter)) { return }
    $ok = Show-Dialogo 'Reiniciar router' "Se corta internet unos 2 minutos, también para los demás de la casa.`n`nEl optimizador entra al router, lo reinicia y te avisa cuando vuelve internet." 'Reiniciar' 'Cancelar' 'alerta'
    if ($ok) { Start-Accion 'router'; Set-RouterUI }
}

$ui.BtnRouter.Add_Click({ Start-ReiniciarRouter })
$ui.RouterClaveLink.Add_MouseLeftButtonUp({ if (-not $script:Job -and (Show-ClaveRouter)) { Start-Accion 'routerprobar' } })
# tocar el globo de "dejó de responder" abre el optimizador y ofrece reiniciarlo
$tray.Add_BalloonTipClicked({
    if ($script:GloboRouter -and ((Get-Date) - $script:GloboRouter).TotalSeconds -lt 30 -and $script:Rt.Compat) {
        $script:GloboRouter = $null; Show-Main; Start-ReiniciarRouter
    }
})

$timerOv = New-Object Windows.Threading.DispatcherTimer
$timerOv.Interval = [TimeSpan]::FromMilliseconds(1000)
$timerOv.Add_Tick({
    if ($ov.IsVisible) { Update-Overlay }
    $espera = if ($script:CapturaTicks) { $script:CapturaTicks } else { 3 }
    $maximo = if ($script:CapturaMax) { $script:CapturaMax } else { 25 }
    if ($script:CapturaLista -and ($stats.Tick -ge $espera -or ((Get-Date) - $script:CapturaLista).TotalSeconds -gt $maximo)) {
        $script:CapturaLista = $null; Save-Captura; Salir; return
    }
    if ($script:EvtMostrar -and $script:EvtMostrar.WaitOne(0)) { Show-Main }
    # se cierra para dejar pasar a la versión nueva: los ajustes de juego quedan puestos, como al actualizar
    if ($script:EvtSalir -and $script:EvtSalir.WaitOne(0)) { $script:Actualizando = $true; Salir; return }
    # modo juego automático (aunque la ventana esté en la bandeja)
    if ($cfg.AutoJuego -and -not $Captura -and ((++$script:AutoTick) % 3) -eq 0) { Check-AutoJuego }
    # router: ping cada 3 s, fila "Router" y aviso si deja de contestar
    try { Check-Router } catch { }
    # pestaña Rendimiento: el recolector mide solo si se ve (ventana abierta, no minimizada, en esa pestaña)
    $stats.Panel = $ui.RendPanel.Visibility -eq 'Visible' -and $win.IsVisible -and $win.WindowState -ne 'Minimized'
    Update-Rendimiento
    # en la bandeja o minimizada: a los 5 s devuelve a Windows la memoria que no está usando (en el Administrador de
    # tareas baja de ~250 MB a unos pocos); lo que haga falta después vuelve solo. Una vez por cada vez que se oculta.
    $oculta = -not $win.IsVisible -or $win.WindowState -eq 'Minimized'
    if (-not $oculta) { $script:OcultaDesde = $null; $script:MemoriaDevuelta = $false }
    elseif (-not $script:OcultaDesde) { $script:OcultaDesde = Get-Date }
    elseif (-not $script:MemoriaDevuelta -and -not $script:Job -and ((Get-Date) - $script:OcultaDesde).TotalSeconds -ge 5) {
        $script:MemoriaDevuelta = $true
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        try { [void][JVps.Shell]::EmptyWorkingSet([Diagnostics.Process]::GetCurrentProcess().Handle) } catch { }
    }
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
    Set-AutoUI   # Set-Tema inicial sale antes de pintar la fila del modo juego automático
    Set-InicioUI
    Set-PuntajeUI
    Add-Line 'Listo. Elegí una opción.' 'dim'
    if ($cfg.Overlay -or $Captura) { Set-Overlay $true }
    if ($Captura) {
        if ($SinDatos) { foreach ($k in $SinDatos -split ',') { Toggle-Dato $k.Trim() } }
        # pestaña Rendimiento: espera ~12 s para que los gráficos tengan datos
        if ($Vista -eq 'mipc') { Set-Tab 'pc'; $script:CapturaTicks = 4; $script:CapturaLista = Get-Date; return }
        if ($Vista -eq 'inicio') { Set-Tab 'ini'; $script:CapturaTicks = 2; $script:CapturaLista = Get-Date; return }
        # fila del router: espera a que se detecte el modelo y lleguen los primeros pings
        if ($Vista -eq 'router') { $script:CapturaTicks = 9; $script:CapturaLista = Get-Date; return }
        # Espacio: la captura sale cuando termina de medir (o de analizar el disco, que puede tardar minutos)
        if ($Vista -like 'espacio*') {
            $script:CapturaTicks = 1; $script:CapturaMax = 600
            Set-Tab 'esp'
            if ($Vista -eq 'espacio-juegos') { Set-EspSub 'jue' }
            if ($Vista -eq 'espacio-carpetas') { Set-EspSub 'carp'; Start-Analisis }
            return
        }
        if ($Vista -eq 'rendimiento') { Set-Tab 'rend'; $script:CapturaTicks = 12; $script:CapturaLista = Get-Date; return }
        Start-Accion 'diagnostico'
        return
    }
    # abierto desde Configuración > Aplicaciones > Desinstalar: si cancelan, se cierra (no pidieron abrir la app)
    if ($Desinstalar) { if (-not (Start-Desinstalar)) { Salir }; return }
    Show-Actualizado
    if ($EsAdminAhora) { Check-Instalacion }
    # primera vez: el asistente ofrece revisar la PC (con permisos, si no la mitad de la revisión queda corta)
    if (-not $cfg.AsistenteVisto -and $EsAdminAhora) { Start-Asistente }
    $script:ProximoChequeo = (Get-Date).AddSeconds(4)
})

function Texto-Instalar {
    "Se instala en Archivos de programa y deja un acceso directo con la paloma en el Escritorio. Desde ahí abre directo: sin el aviso de Windows y sin ventanas negras.`n`nSe puede desinstalar cuando quieras desde abajo a la derecha."
}

function Check-Instalacion {
    if (Test-Tarea) {
        # ya estaba instalado pero abrieron una versión más nueva del .bat: se actualiza solo, sin preguntar
        # (o lo instalaron desde el .bat y ahora abrieron el .exe: se pasa a usarlo)
        # (o el .exe abierto es más nuevo que el instalado: las actualizaciones de GitHub solo traen el .bat)
        $exeNuevo = $Exe -and (Test-Path -LiteralPath $InstExe) -and ($Exe -ne $InstExe) -and
                    ([version](Get-Item -LiteralPath $Exe).VersionInfo.FileVersion -gt [version](Get-Item -LiteralPath $InstExe).VersionInfo.FileVersion)
        if ([version]$Version -gt (Get-VersionArchivo $InstBat) -or ($Exe -and -not (Test-Path -LiteralPath $InstExe)) -or $exeNuevo) {
            try { Install-Optimizador; Add-Line "Instalación actualizada a la v$Version." 'ok' }
            catch { Add-Line ("No se pudo actualizar la instalación: " + $_.Exception.Message) 'err' }
        }
        # mantiene al día la entrada de Aplicaciones instaladas (versión; y la crea si se instaló con una versión vieja)
        try { Register-Desinstalador } catch { }
        $ui.UninstLink.Visibility = 'Visible'
        return
    }
    # sin instalar: el link queda siempre a mano, aunque hayan dicho "Ahora no" al cartel
    $ui.InstLink.Visibility = 'Visible'
    if ($cfg.NoInstalar) { return }
    [void](Pedir-Instalar)
}

# el asistente de instalación (interfaz\instalador.ps1). Cancelar = "Ahora no": no vuelve a aparecer solo
function Pedir-Instalar([bool]$conInicio = $false) {
    $ok = Show-Instalador $conInicio
    if ($ok) {
        Add-Line 'Instalado: la próxima vez abrilo desde el acceso directo y no pide permisos.' 'ok'
        $ui.InstLink.Visibility = 'Collapsed'
        $ui.UninstLink.Visibility = 'Visible'
        Set-InicioUI
    } elseif (-not $conInicio -and -not (Test-Tarea)) {
        $cfg.NoInstalar = $true; Save-Cfg   # queda el link "Instalar" abajo a la derecha
    }
    $ok
}

$ui.InstLink.Add_MouseLeftButtonUp({ [void](Pedir-Instalar) })

# "Iniciar con Windows": usa la tarea programada, así que necesita la app instalada y con permisos
function Set-InicioUI {
    $on = Test-Inicio
    $ui.InicioToggle.Background = if ($on) { $Colores.accent } else { $Colores.toggleOff }
    $ui.InicioDot.HorizontalAlignment = if ($on) { 'Right' } else { 'Left' }
}
function Toggle-Inicio {
    if (-not $EsAdminAhora) {
        Show-Dialogo 'Iniciar con Windows' 'Hace falta abrir el Optimizador con permisos de administrador para cambiar esto.' 'OK' '' 'alerta' | Out-Null; return
    }
    $prender = -not (Test-Inicio)
    if ($prender -and -not (Test-Tarea)) {
        # para arrancar solo al prender la PC (sin pedir permisos) primero hay que instalarlo
        if (-not (Pedir-Instalar $true)) { return }
    }
    try { Set-Inicio $prender }
    catch {
        Add-Line ("No se pudo cambiar el inicio con Windows: " + $_.Exception.Message) 'err'
        Show-Dialogo 'No se pudo cambiar' ("Quedó como estaba.`n`n" + $_.Exception.Message) 'OK' '' 'alerta' | Out-Null
        Set-InicioUI; return
    }
    Set-InicioUI   # el interruptor cambia antes del cartel, así se ve el estado nuevo detrás
    if ($prender) {
        Add-Line 'Iniciar con Windows: prendido.' 'ok'
        Show-Dialogo 'Listo: inicia con Windows' "Al prender la PC el Optimizador se va a abrir solo, sin pedir permisos. Si lo cerrás con la X queda en la bandeja, al lado del reloj.`n`nAsí el modo juego automático y los datos en pantalla ya están listos cuando entrás a jugar." 'Genial' '' 'info' | Out-Null
    } else {
        Add-Line 'Iniciar con Windows: apagado.' 'ok'
        Show-Dialogo 'Ya no inicia con Windows' 'Al prender la PC el Optimizador no va a arrancar solo. Lo abrís cuando quieras desde el acceso directo.' 'OK' '' 'info' | Out-Null
    }
}
$ui.InicioRow.Add_MouseLeftButtonUp({ Toggle-Inicio })

# ---------- desinstalar (desde el link de abajo o desde Configuración > Aplicaciones) ----------
# 1) vuelve atrás los ajustes que cambió (red, energía, Game Bar), 2) borra lo instalado (Archivos de programa,
# acceso directo, tareas, entrada de Aplicaciones), 3) si querés, también la configuración, 4) se cierra.
# Devuelve $false si cancelaron.
function Start-Desinstalar {
    if (-not $EsAdminAhora) {
        Show-Dialogo 'Desinstalar' 'Hace falta abrir el Optimizador con permisos de administrador para desinstalarlo.' 'OK' '' 'alerta' | Out-Null
        return $false
    }
    $respaldos = @('red_respaldo.json', 'juego_respaldo.json' | Where-Object { Test-Path -LiteralPath (Join-Path $Raiz $_) })
    $texto = "Se borra todo lo que instaló: la copia en Archivos de programa, el acceso directo, el inicio con Windows y la entrada en Aplicaciones instaladas."
    if ($respaldos) { $texto += "`n`nAntes vuelve a como estaban los ajustes que cambió (red, energía y Game Bar)." }
    if (-not (Show-Dialogo '¿Desinstalar el Optimizador?' $texto 'Desinstalar' 'Cancelar' 'alerta')) { return $false }
    $script:BorrarDatos = Show-Dialogo '¿Borrar también tu configuración?' "Tema, juegos elegidos, datos en pantalla y registros (carpeta $Raiz).`n`nSi pensás volver a instalarlo, conviene dejarla." 'Borrar' 'Dejarla' 'pregunta'
    if ($respaldos) {
        # restaurar la red reinicia la placa y tarda unos segundos: va en segundo plano y al terminar sigue Finish-Desinstalar
        $script:DesinstalarDespues = $true
        Start-Accion 'restaurar'
    } else { Finish-Desinstalar }
    $true
}

function Finish-Desinstalar {
    try { Uninstall-Optimizador }
    catch {
        Add-Line ("No se pudo desinstalar del todo: " + $_.Exception.Message) 'err'
        Show-Dialogo 'No se pudo desinstalar del todo' $_.Exception.Message 'OK' '' 'alerta' | Out-Null
        return
    }
    if ($script:BorrarDatos) { Remove-Item -LiteralPath $Raiz -Recurse -Force -ErrorAction SilentlyContinue }
    $fin = if ($script:BorrarDatos) { 'Listo, el Optimizador quedó desinstalado y sin rastros.' }
           else { "Listo, el Optimizador quedó desinstalado. Tu configuración quedó guardada por si lo volvés a instalar." }
    Show-Dialogo 'Desinstalado' "$fin`n`nGracias por usarlo." 'Cerrar' '' 'info' | Out-Null
    $script:Actualizando = $true   # Salir no tiene que tocar nada más (ya se restauró todo)
    Salir
}

$ui.UninstLink.Add_MouseLeftButtonUp({ [void](Start-Desinstalar) })

if ($Captura -and $Estilo) { $cfg.Estilo = $Estilo }
if ($Captura -and $Tamano) { $cfg.Tamano = $Tamano }
if ($Captura -and $Tema) { Set-Tema $Tema ([bool]$Claro) $true }
else { Set-Tema $cfg.Tema ([bool]$cfg.Claro) $true }
Set-PerfilUI
Set-Tamano $cfg.Tamano $true
Apply-Admin
$ui.BtnOverlay.Foreground = $Colores.muted
# capturas de prueba: fuera de la pantalla, sin foco y sin clics (una tecla o un clic perdido apretaba
# botones de verdad, por ejemplo Limpieza, mientras la captura esperaba)
if ($Captura) {
    $win.ShowActivated = $false; $win.ShowInTaskbar = $false; $ui.Root.IsHitTestVisible = $false
    $win.WindowStartupLocation = 'Manual'; $win.Left = -20000; $win.Top = 0
}
# primera vez sin instalar: el instalador sale solo, antes de que aparezca la ventana principal
# (como cualquier programa recién descargado: primero se instala, después se usa)
if (-not $Captura -and -not $Desinstalar -and -not $Bandeja -and $EsAdminAhora -and -not $cfg.NoInstalar -and -not (Test-Tarea)) {
    [void](Pedir-Instalar)
}
# también al prender la PC (-Bandeja): se muestra la ventana al frente, como desde el acceso directo
$win.Show()
[void]$app.Run()

# ================================
# LOGO (paloma, JPEG en base64)
# ================================
#LOGO:/9j/4AAQSkZJRgABAQEAYABgAAD/6xaJSlACEQAAAAEAABZ/anVtYgAAAB5qdW1kYzJwYQARABCAAACqADibcQNjMnBhAAAAFllqdW1iAAAAR2p1bWRjMm1hABEAEIAAAKoAOJtxA3VybjpjMnBhOmQxMGZhODFkLTg1ZjgtNDQ4Mi05MzljLWY3MGZhYzIwMzk2NAAAAAOUanVtYgAAAClqdW1kYzJhcwARABCAAACqADibcQNjMnBhLmFzc2VydGlvbnMAAAAAuWp1bWIAAABEanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5pbmdyZWRpZW50LnYzAAAAABhjMnNor1mOmPWNmO7GZAW2HxpiTQAAAG1jYm9yo2lkYzpmb3JtYXRqaW1hZ2UvanBlZ2ppbnN0YW5jZUlEeCx4bXA6aWlkOjcyYjQ1OGZkLTY3MGUtNDVmZi04MzIxLTk5ZWRkOTliYzUyY2xyZWxhdGlvbnNoaXBocGFyZW50T2YAAAHianVtYgAAAEFqdW1kY2JvcgARABCAAACqADibcRNjMnBhLmFjdGlvbnMudjIAAAAAGGMyc2jxagAckud06wHuKCpIzOtmAAABmWNib3KiZ2FjdGlvbnOComZhY3Rpb25rYzJwYS5vcGVuZWRqcGFyYW1ldGVyc6FraW5ncmVkaWVudHOBomN1cmx4LXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaW5ncmVkaWVudC52M2RoYXNoWCCaw0117doiKVurSRWpfGvXorEvKbj3qyozCQCzeEM8jKRmYWN0aW9ueB1jb20uYW50aHJvcGljLmNsYXVkZS5wcm92aWRlZGpwYXJhbWV0ZXJzoXgfY29tLmFudGhyb3BpYy5vcmlnaW4tY29uZmlkZW5jZWd1bmtub3dua2Rlc2NyaXB0aW9ueGZDbGF1ZGUgcHJvdmlkZWQgdGhpcyBmaWxlIGF0IHRoZSByZXF1ZXN0IG9mIGEgdXNlciBhbmQgbWF5IGhhdmUgY3JlYXRlZCBvciBtb2RpZmllZCB0aGUgZmlsZSBjb250ZW50cy5tc29mdHdhcmVBZ2VudKFkbmFtZWZDbGF1ZGVyYWxsQWN0aW9uc0luY2x1ZGVk9QAAAMhqdW1iAAAAQGp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuaGFzaC5kYXRhAAAAABhjMnNoTVDVD3VWDvjiMghrzIGTVAAAAIBjYm9ypWNhbGdmc2hhMjU2Y3BhZE4AAAAAAAAAAAAAAAAAAGRoYXNoWCCHx1Wi9Lnbc96IXrZNVhIvzE2PbQHgyK2uD7aAzYg9yWRuYW1lbmp1bWJmIG1hbmlmZXN0amV4Y2x1c2lvbnOBomVzdGFydBRmbGVuZ3RoGRaLAAACPmp1bWIAAAAnanVtZGMyY2wAEQAQgAAAqgA4m3EDYzJwYS5jbGFpbS52MgAAAAIPY2JvcqVjYWxnZnNoYTI1NmlzaWduYXR1cmV4TXNlbGYjanVtYmY9L2MycGEvdXJuOmMycGE6ZDEwZmE4MWQtODVmOC00NDgyLTkzOWMtZjcwZmFjMjAzOTY0L2MycGEuc2lnbmF0dXJlamluc3RhbmNlSUR4LHhtcDppaWQ6NzhjYTRlNjgtMmZmMC00NjQ3LTk2ODctNGQxNzVlZjJlM2ZlcmNyZWF0ZWRfYXNzZXJ0aW9uc4OiY3VybHgtc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5pbmdyZWRpZW50LnYzZGhhc2hYIJrDTXXt2iIpW6tJFal8a9eisS8puPerKjMJALN4QzyMomN1cmx4KnNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuYWN0aW9ucy52MmRoYXNoWCDR3AfhFrez4jmmLjKbYAcaWiRjFLAeLR4W0p0TE/pzHaJjdXJseClzZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmhhc2guZGF0YWRoYXNoWCDzZhsah/1I3aSNenXecHPEifv41tlWaYX/Rla42MInfnRjbGFpbV9nZW5lcmF0b3JfaW5mb6NkbmFtZW9BbnRocm9waWMgRmlsZXNndmVyc2lvbmUxLjAuMGtzcGVjVmVyc2lvbmUyLjQuMAAAEDhqdW1iAAAAKGp1bWRjMmNzABEAEIAAAKoAOJtxA2MycGEuc2lnbmF0dXJlAAAAEAhjYm9y0oRZAhKiASYYIVkCCjCCAgYwggGNoAMCAQICFEDloAruwjnQvriD+gZCBT1nVRMAMAoGCCqGSM49BAMDMEkxFzAVBgNVBAoTDkFudGhyb3BpYywgUEJDMS4wLAYDVQQDEyVBbnRocm9waWMgQ29udGVudCBDcmVkZW50aWFscyBSb290IENBMB4XDTI2MDgwNzE4NDM1NloXDTI4MDgwNjE5NDM1NlowRDEXMBUGA1UEChMOQW50aHJvcGljLCBQQkMxKTAnBgNVBAMTIEFudGhyb3BpYyBDbGF1ZGUgQ29udGVudCBTaWduaW5nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEmHoKa8tQGAUU1TS9QqU5W0Tp2N3XsvlK7BfQt6YWKwEzd2R3/dzKPEUDdCjlLjp9fT+KFjRVnuZ9v0oXvTe3k6NYMFYwDgYDVR0PAQH/BAQDAgeAMBUGA1UdJQQOMAwGCisGAQQBg+heAgEwDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAWgBTOUeIEgU5kWyP448TPmj6cwddcwjAKBggqhkjOPQQDAwNnADBkAjAxcx0UngF60stVjs5G4T2eiptsBk5mf9oCtfJPAUBl8qs/PEXa8+gk1/X5QJ2DVcYCMHBfXN31YapiSqYvlIWrDVDJKOvXMl+kkz37Wt0PBI8sw486Mq6JeOhT+lRR4b1HCaFjcGFkWQ2eAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9lhApAtc5dn02F4mCAw0cuVtjpVGid8udn+r7J2+9SKEBVCq1LmCTmL98+xsRIrOwU/FPCY1da69qRLvCbxvXLnKk//hADpFeGlmAABNTQAqAAAACAADURAAAQAAAAEBAAAAUREABAAAAAEAAAAAURIABAAAAAEAAAAAAAAAAP/bAEMABAIDAwMCBAMDAwQEBAQFCQYFBQUFCwgIBgkNCw0NDQsMDA4QFBEODxMPDAwSGBITFRYXFxcOERkbGRYaFBYXFv/bAEMBBAQEBQUFCgYGChYPDA8WFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFv/AABEIAQABAAMBIgACEQEDEQH/xAAfAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMABBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEBAQEBAAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APc2bbTS+4Y4pz7SuARz3qL7px+td/NZmTa2ZWl/1zDsKa3WpZEG8sTjNRP94gdqxkFtBydR+FLSL94UprA2i7JDXdFOGYAmlLALuzxQVB7U0x543HFBb5pDtw4x3pcnpgZpuzGOc4p3fpSduptFyVkxyHJxjpTse1QsSDwM0GQqPmTH41lJNM0aZNSFfrUYPt+tBbn7v61nzeYuVj2Qd81Wuby3t0OXBYjgGk1G5+zWjynoB1z7VykuorO5ZSGPfJqlK7JkkdDDqBkkAxjd3q/as03Gc81x9vesJV4GM+takGqLERucg49a1sibaaHRAxg4woI71IG5HofauYl1oI8YEw+ZguPrXQQuwRG3buOvrRZGLjJlng0hAHWozKc5IAp1xnYNpxUt2JVOQrbegprfdNNiBGc4NPwCcHpVRd0Jq2hdhAKAe1KEIGO1JAyhPvCpN6/3h+dB0qKcVcjdBnk06NFHI5NOGDyMGmkANnOKtSjawSirD6KAQRkGlKt6VDOYSlTrQQcZ3L9M80L3rrp7kvQyyn+zimwncScdKnPpSKqoMKMVpyozUUiKVSV9KiZfm61PIeCAwPNQuQGrCT0Nkk0HSioyJOu4UAS92FZFKy0JKdtHY1DtkH8QpUZwOXHHvWU5NPQ1hKw9gQeBkVFK7qw2j61IXbJweO1NJYn5ufSo553N2m1oR+ZIPWl3M/J5p5XNAUDoKOab3JUWOJyMU08DgUE4FCsCKlKxpc5f4q3ctt4VmeI4JYfhXnulaw8sQUc7VHeu1+LV1GLEWmQRIeR715utuVXbGQAOmK0itTC+rOlGq7Ngzgn05xU8t9I+XHOOtXfB9l4fOnobmZXucAspbOKZ4nfRvOWOwlMb4wy9a0C5RjMt5eWwUgBZVY9q9R09w9smCTgc5rzPR2h+1KVIwp45r0fQpY2tThuo7Gmg5ki8GwTmpVkUjiq4p0WA/NJpWFzpk7cx5ptLkeVgUlJbGU3dihsDApd5ptAJHSiwlJrYsRFlB56+lLECH+bNNgYsCW60/djgsAKdkUpdyXB3ZHT0p23I+6v4tSb17GjeuKVjOzFAwBxjinLTFYFiM09a64EMoyfe49KYXOMUKcxU09TTlqwjqiIN85znn0pGwWzQ4ZT04NAOazlsWn0CiiisigNNIIGT0pW6GmAZHJ96znFyLjYUEEUtRp9+pKhXOmL0CiigEAgntRYoazAjim5CqWP8IzUkxQkYxiqGsXKWlnK7DO1c4pRd2zJuzPM/ilei711lD/LEQvXrXKXNytucIDz6GpNfvluNUnk/vOSM1myvu55yKtEmloOpRR3jys4GcDg9Kk1O8T+0GeKUHPHWubLbJCx/iNOt87953bfXNWFjsNHuXjIYsMCu78I62RtDONvcE15VZ3CxpjzDn861tI1gwfuyc5PFBlO1z3C0nWePevSplGWArj/BWuJKhhdjhgOvauwQhyAp4qkTcmHQUUCipJEz82KWiigCazIDHPepZ1WUbFbGaqgkf/rp0blWDHoOvNFrmkZ20LI2qNpzx3ApR938KFO9AaXAwee1bRi09TZrQapwc+lPV8tjFMHSitDnauVSNoOM803P0pSwIxUcjADH605WvoZbIYSXbBNBGDimhtvODigODySPzrKTVioiSOVbGM8U3zTnG39aScgvkHtUbMRzx1rK5XoTLJkkMNp9DSLyKYrFmOfxp2Dms5s0iu48ADtzS01AepI/CnVKZ1LYOpxUSkkdT1qUHBzTFQg4yOTUyFJMjkYg9a5X4paqljorI7ZeVcYzXSX8ogDM3QKT1xXivxU8QPf6mVAzCuQFB6ULQzObkuA0rEDIz1zQz8dDz71TtSfuqTy2avRx7wR6c9OtaRv1OdzsyvIgdvm6dqimkkicKjDaBnmrMsLBDhsfhUJjcoRuXp6VZLq23ZPBNM4yETB7qOtXk4QENz6VU0sFINpNSPK4l2DGDQLnUtjo/CeoSwXa/PjB9a9k0G8FxZRszDcV5PpXgMXmQKJlccHOPWvQ/h/4jzZrFOwAoNYRTVz0vJx940oZh0OfrVWxu4rmAPGytxng1YhkypIA59qbaG4RXUn70Uu096NlTcybQlOiAZwr/dNGylACkMegpxavqCaLOQFwvAFAxUAmAB460iTNuy3Ix0ro549zSUr7E0jbEzjNV975zuYZ96dLKGTbjFR0KaexnJkBVgOc009Ke0hZcYH1qORto9ar1MxW3BMnO3t6VC+N3FK0hIxwBTQQelYzWpSQU2Q8U6myEgcHGazLQsLgAl+pNPLrUStlcHrQVI61Fr7mkZN9CdT6Uu4+1RBsDildyOOOfWsmmuptqh5YjrSM527gfpUMztkAHiqupXv2S1eZsbUUkk0K9wu7HL/E/wASLpenNbgBppQV/wB2vFtXuXnuNoOS3Jrd8eao+o+IJJZJAEyQoFc0QTP5nfoKq5LHwhlwGB4q5p7lJ8sTg9O9UlmIbkjjpVkyqBkOM+1ax2ORxTZelwXJXoabMncAYFQx3yFVAwT7inCcHvVOUUKUL7DXLIPlyM0ltKolO/PXnPU0pdRzxVdmHms2R19aSdyVTkjSMseCBkj0qxpF+1tIq54J4rF+0kMSdtSpOJOmOKEdcFdI9T8I6/cpcKgXKsQD81ek2cyTWyuuBkdK+ddI1F7XaQ5LDsa9a+HviJbuJLWQAEDjBp2ZXKjvPOTGcn8qcjB13DpVZex7VIJNpGOh61nKLIdOPQmGKRvu5xTGkB6GlByucg/ShR6mPJZirww+tPnZDwoH1ApijIPY0mCOtXcYUUUc5px+ICuT6nrUdwQACPSo95Yk9OenpRyeCc10kIbKcqDUau4H3KlOO+MCo2wWyKia0Li7gGLHJyPb1od+RkEgU1iB1IpsjjGFOfpWLaRSFMnONpojcLkAMx71ESd3U0mTnI61zyqX2NkrIuAZxk4BprgA8EmoopPlAduacHUj7wo31KauhDgMWLEYB4PeuJ+K2sNDpTRRuQpODz19q6bWrn7NZtuf5icDB615b8SJJpbRnkyFL5GTSQtdjib9kaXzf73JNUjc8kKv60y8nxL9446DmoPOi/vVoo2GWlkB5xU0arjcB1FZwmQHh1xT/tQx/rSKohRRoRnBDYqTzMjjJz7CsoXKgf6009JnZcq5xU2u9R8qL8h45/xqnNNGkpyW69McUwO4/iNVLmZgz/Od1Wh2Re86Jh0xU+nyCJfmHX1rCNwwPLHipEumDZckj86YJW2OkinV2XAOCeua6/4e35ttYQK2MkZ9685tLo7lIJ25ro/DV1ImoRt1yw5q4ysgkfTVg6XFnG6kDKinupQkE1jfDy/gurOFS+fl5zXRX8aohIHXoc0rmUb3Kitk8VInyZfrUY5GaXJxik1c1ai0WEcMm4c47U3OeSMVCpIGAcDParCgdcUoxbMvZdhtFBHNFOPxGTM2PoadTFOKXdxXT1JimlqNJZjtIAB75pr4U49KHJBBHOOtRSEO5OTzWdR2RUVqRuzE8nOKVKRlwc9c+9JOR5RG0ce9c7dzRJpj8dTmkpsLYjp1c8klsbIKD0oqK5fy0LEfKBkmklcGzN1wG4vFRm+UYzWJ460W3n8OOkRO8DOeKme58y5Z3YlT0FNkmhdSh4DcGtBng+qxtHcmNxhlYiqDAflXS/Ee0S01+YIuNzZz61zDnaeec1pfuLqHHtRketRMcnPSk49RU86L5GTZHrUscromBjFVR1p/mH0pqSZPKy41yAowMn3qnLIzSEnHJpsjbhgDFNUjpnNDkUogcZ+9inKM1WuB+9B9qeJRgAg04sTL1tJt2qMcGum8Ir9q1OKFl+UOBkVyEB3MrDj2ruPhpJjW42YDkjNWSe4eGjFpqxiPbjaB711a3ZuIQxAFcOkqFFwp4HrWpoVy27ylYhQeQaNSWn0OkBHrS8VSRyy5AqYMyqCMYppmbT7E/wCFTjhB9KrIdyAnvUiMF69MYrSLsXAk7D6UU1ZFK4Kn86Xcp6A/nUxi+YylGzMwkKCTxioLhgQu0n3p0nIbnOe1QsSO3SumySuyHINzAcE05T8maa0hC4G3H0qIyEcYrkqO5pHQY8sjHrijzXIAyD6008kZpGGKxWpstSRZWyBhcfWpy6/3hVQ06olFXHexaJAXJ6etU9Zlj+wPtbHHU1I0p8ry8dsZzWfrrBNOkPGSOM0nGyBnJy3SKoLShsmmrdo5ADAg9aw552Vjlu5xUJmfcGWUAelCSaGZPxYRWkjlRAzZILA9RXBXZO0fWut8X3bTXCxsMgZ5rmbyErCztjAPFagVf4AKaRinIR/hTbg4UHNSaReg5PWnU2LmMGnUiroQkDqabhsgj1pJO9OUjaOtMLkNxnzh9DTadcEmUcdBikCljg5A9a0jsYsmssllA7Hmut8CXflaynPA6Edq5a0URp1zmtfw3IYb8MOc9KYkj2iHVojabmcFh71u+F7qKaLeJQWbtnmvMdLuJJBtbG1q7XwGx3BCM4phdHoNo37pQepqw2AmDVSA5RD0wBVsn5AaXUUmmtCWH7lPXbn5xxVcSN61Kjbh2zVmcZWJi0WOFzTdygnsKbSE4IrWDCUlymVLweOPxqvNKEOCCask5U8H8ap3Y+bkH2qr33OdDDMnqTTTPFnk4qE9aCB3Fckldmik0SNKjONjE+tCuC4ABqIY6DFBfYcgjINS1ZaDi3ctYHpSgVB5j+tSQM7tjIqGbWe7HkVneKXWPR3Jz+FaNY/jXd/Yz7Rkd+KRXLpc801JlLZBwM1SabaPvdOaTUZpFcg4x1HFZt7M3kyNnnaeRQmth6NGVrk32jVvkJIGc1EyhlIaqqO/myPznPU1aXpn1rQCk8C85wMdMVXKkjlfzq9cj95nnHtUJUAjBJ+ooBMrhSBgDp70+MHHIqbaKI1XHzdaEkDk2RlR6UqxbuMdfapQEB4/nT/NUDGOntRdBdld7XbhmCk+tEMRL4HX3qwHLueOB0pYVXzOB1HNClYAjjbcAyg0WzCLVUBbbzwKswKA+QKy9QYjUI3U8g/1q0B3mmOpVQrc59a9D8CxyGVcHPSvK/DUpeWMOR1zxXrvw/B3g44GKZMlc7e2UeUMjB+tSquOf61HE2c5bGKlHTOaDJwYppyq2M4NNpQDjPP60EXF3MrfNk+2amikRn2kY9KrkknmnIwE4Ynirg/eHcrzR5zg9vSoGiIGT6VtzWeG+RAR61Xu7EvGQRtOOMVs1oY6o56e3KhnznnoKrngV0P9mkptJ7c89ary6TGpPAxjPWuZrU0Rz9wdo4JGRUYl3EK3Wtm60tGUYyfpUK6UVfIjY49qmWxS3KccqBArNgjjpU9rNhiVGRU62HOGTH4VKtnGv0+tYpHQndEa5Kg461T163e40qdF4+QnOK1oouAoUMaV4yCIyg2sDnvQGp4Dro2SuMElQc1yV1dMXdBkLyOtejfF7TG0y6kkWNhE4J3AfXivMmxJISoJyc0uoMWJC468CrDMEjz6Uy2BVSCMc1G6yAncGx71t0GPaVSpGDz7VD3pcE9qQ8daRLuFMDE05iMcGoUBDc0JAokgbntTgw6d/pUY+/UyYweO1OyHYEJUkip40w+7Paq9WY3U/KKlLUS0JYyc8Vlaguyf8c/jWkTgZ9KznxJd4Ldea1Qzc8J3Ja4T5CTnAxXvnw8txHpaysTlscEdK8X+DuhXGpa+fKBaNW5zwK+h9Osfs0SxKuFUDPHemiZaEyhSe9ToPlH0pHX0WpYoZTg7ePpQzNS01G96D1qzDbkknBPpxT0smY8KR9aRBTpGQ7sE1oR2W2Ub14+tTLaIxyAB7HmqhuBHFfQlOW596Sa7hZfvgVyqXEhHJ6e1QzXUgYfMeewrWctCGzqWu0IAVQx/Ko5LlDkFMcdM1zE15OiBg/SqsuoXBYt5rDA7mudstHUPKoX5OuaabrYm4gg1yZ1a5I5bvTTq875XeSB2qHI0jG6udX9r3dAD65WmmVMcJ9c1x0msTRykBiD1xmkOvXOOSfyqeZo0SsdpFKuRgc9hmpxIqjnA+pri4tXmMQctjPpTbjXvJTzJpMKO54pdB7G/4u0ex17S3s7h1BcfK2MYNeC+O/Ckfh3UhFBOJUP3jXa+MfiZBaWbQWZDu3yh89K8+/tWXVYJZbidpX3ZBap5kMzJQFbCg+9QSbiu0j9K0JcDHaq0pJIq07iaKyghcYqKUZc1cPSqkow5p2swsM2j1pp5bg8VOkO5QwIzmkkG18HBPtVXBuxGQvqcinDpS5oUc8kc0bkuSEx7/pToyyvkZz9Kk2jHC063Rs5LHJ4+lCVhKVySNTJH05I6UzTNC1a+1MJa2UkgJ25A4x9a7f4UaAupauv2hVMIILEjivcdHtNK023EUFtCAPQVSLbZlfB/wcmg6BG1wP378mu7t4YGjyx5z/erOW/t8Dj8AeKcmoQbhwOO5pmMpNmm1vD+P1py28QHAJNUG1O3/vDp60LqwC/Jg470WJsaQjUDG3H0oRApyCx+pzVBNUEhJbJ9KedQUHDAD8aBGmqxAYbaT6k0qrDnjYPxFZgvoTzhfxpRfRZ4VKqLtqB5+08h4z19qrzzsh5c06VtkZb0qrKBJgscVUyUPNyp6sf1qC5uF3kBlxjoetQScc4qtcYbLnggVi3cbdiR5Y1blx7VGb2JGI3A4rPuJWJB3ZFVZ5W2EBeT3xWb0OiKurmq+oIZM7R6dKa+oRkYI61ibm67jTLmclFHHX0qLXZR0EV5b7cF2HtmqPiF4Lm1MGCwKnFZCuwYEZ/Oo7mZyRgjP1qlo7AczqHhieR2Ky4AORk1QtNN1KzujG6goTyK66W4ZR8x3D2qJpC2SU6jrReOwHOXO7fjBGPaquSW5rQ1zdv3HsccVnxqGkCt0pRdg1FyMdajljDYAWra2oxw2M9BQltcMD+64HFXe40yiuVGOmKbNknNaX9kXrfMIWweelNfSb9efs5xj0pDdmZ0a7+OmPapgFROe1TpZXCnJiaqWpu8TiMxkZ9quIrE3nIOp5qzpcDXt9HDDksxHasiLe7bVXr2rvPh5Zrabbl13sBjBqrC5T0bwNpMekWCbSpkbBJ9TXT28krklyp5421yGnX7sEGcDpj0rYsbqVdwVsUwtc3R05oLD1rNSeTGS360G7ZRxtP4UcxnZGkCD0P6Uucd8fSspr2XbzgfSpEvnMYyB+Rp30Dk1NNZ5F4Uj8aUzuecjPtWat3Iy/dXg0ou3HGxKmCbKsupq28r5xu79jxUjTFfvMayoLx1faEA75xxTvtjsCZU5HpTSszK1mYktwHQrtxn3qs5A75+lOyKil4Iz3q5mY2dxs9KqzsCjDg8U9yWkwScZ79KRlQKc4NYbBcyJF3IVBxVds4KntV+eE5BVO3OKpTIwLErjBqXqdUfhRAzclTxxVOeQJGCQT2qa6ZlfcBxjFVzhzgjipVkUR+cuecfnTZJ4x979KhmOJWHoaqX+7epGcY5pqz1JJJJ0XnnGab9pRhtB5NVnYsMMcinWVtJdXccMIAP9aOS7uND7yJ5rcqo+b0PWs6OwmMqhlAHrUt1eGz1Jrac5aPqQSajbX4jKqRxl2ZgB7UWSA6XT9MiaNFYDd/Sti0sIYk2iMc1R0mUNAkpGDj8q14pEKjDUrsY8JAqjMZGPypC8QyBGGGOuKHYN3qC7k8teAQexAppsCrdWsKsD5anNYHiCyt3ulPlgf0rdmmJ27m496ydbcG2mmxyi5HtWkWNFCy0uBpt55x2re0+JbdFQEYBzxXO+FtXtbhB5j8hsHPHNa8d9HNdhIm3AnoO1WB1Gm3KCRRg8kVuWtwoOCG+b2rm9LjcTqzA4HrW7bsgAJ6460mI2I5QUA2npSkgrgLj3qukqbRhh0p3nL/eFFh8qHsCxxkCpAHAHzY/GqzTgNhT+NOMr5ByT6VLbBplgvIpxtBx3ojZmJ3KB7iokkZgRnFO3Pj72aSlK2hLuTefhf8AV9O+akjfzEY4xiqm4k4LcGnhigwkg98VabvqYaJmZNkISKrs5bGWzilZHBJxx9aiIJPT9a2lHqZJXYTOVXI70xnJGDSMu0kHrTDwa5Zb2LjG7GyttOaz758pIT69hV+UFiCB0pRbK6/NxmovbQ3SOeuHLLjBH1qtI/yBh3rfuNPCDcwzms+90sNHuR+nJBpSfMWYkrbpC3rUV2MwnkdKnvImQMgHQ9aonuKUbkt9yE8dRVzwudutwqCAGJGT0FU5G2Ese1TaKEa482SCR0J6r6d60i31EO8W+HtUs72fUVijmt3+8wbpXNaVp3m3H2kHCq2eO1dT4qktf7Le4tNXkRFyGtn7VkeF5I7jQZwXVXD7seopNXBvyOo02QrZL04q9a3BDHZg8Y5rB0iXFqgJJz0rQiYK5JOKVrF3uaj3TIwG1eR1pJ5jLFg44FU1lJ525FHnALhuCemKqIEU5yozWdq25rSSNccjFaAPPLZHpiqWtxs1tuwMZz17VadhI89nSWwuyPN+Rm5wa2dAv3h1yBoN8it1LVl+NJ4WuYolGCgBbA4rsPhNfxMiRw6H9plxkt6DNUncXMkzvElEqq4UKGAOK0IDmLPc1BPLPcFQ2nC3A9+lWIFITk5zQ43ZRcU/KKXA9B+VV4iTMg3E/WrFK1gHwJvJ7AelTkqAB19KrAkDjvTlYkYxSlsGpOGweKdEwJIqusYzwSamhU/e9RikrLUXMSOBtpYlLDjHFNX7w+lPq2znm7mL5rMpBYUAAkVCUG4Hn86k3gAcqOK3YoOw6aPPzckntUPCtygyKcs5xjIJ9jUU05DjKhie57Vztq4J6k+xSM4FJIuF+UdKijuAzcMOO1OEpJyCuPrWMotvQ2jNbEcmWyDz9aqyIQuHGBV1hzk4GT61HdDKBcZxQ4lq5g6vFEDgLgfWubujGkr/ADcg9M10XimWKGDcxOQOgrkJpJJZBIY2WNu5GaLO4+pY2mU4Veg5GetXdHkjiieOOV4Z15EbDhx9TTrSztJ03Rzbgo6qec1R8VTS2VsYp3V2AJjkQYI9jWySsKxz/iu9+33rzmBYv4SFOMkd8VmW88kfyq+wMOR6ii+D3FwjMCVz13dTXZeF/BkEtkb3UZlVUAwhPJFZzV9hmv4ft0l0iBiQGK1oDT2HOQahsUjhhEVuhEaHC7quyTMwAxtxUiRnzCWIHKgYPBqs7sylt3IFakg3KR3NZ88WwlSwyeemKfQZT+1OAQzDI9sVR8Rak8eksykHHXmn3W0THdgemapapam8sngjYAv0oirMTOAvLh7m6eVzkk8fSum+Hus3llPHbW9wsEROHfuBXP3+lXthIyXEJAHII5GKhtJQkoJZlGedp5xWysYNNHvFlcWr4aPVbm4mGG2hMg1t2UvmRgEupA7rivMfButz3EH2a0njt44VwZZOv1rt9B1K1QBJ79riZsYwvFU7dClKyOgHAGGOR6ipopPk+Y1WWUMeFwD6mpYk3YJbijSxammWKQuV6UtI4z+FZy2KewqySswx0z6VNLNhcKQMd6rZkXnoPak+YjpUIyUu5ejdSQcjGOual3LjO4YrPwqpwMUm9s4BwP51pFaGb1KdRXEZkIwBxUrBlHII+tMLN0AP5V020JatuVJVbJA4I681BJFK2SFPHfNWXB8wkg5zT1G6PB71jKCeoo3uY/l3RbCbs/WoJpNQiduPu9s1qzBFI2OffmoZME5IyO/vWbVjRaMow6hfKwBUkfyqbUdV8pSrrkgZIyeKsqkRTJjxWRrkBmZvKUkbetI6UVLGeTUdRDyQl4UP3c12tnpPh+6sjG8HlAjuuPyrzjwrqx0zUnSbs+Oe1esaNqmmXtikkgjLY74qk0TJ2RwHiLw6fD959u0i53xdXiPP6VxuqjUNTunMUErI7Hjb2J7V7zPFpLpl1iO71ArN1e50aw0yQ28UG/aQAqjINNshSkzx6z0yO0O25csVGRHjkH3roIrxpUC5KgDAArLkVmu5pXzukcnPqKsW5CL15rFyfQ0NKKUhcbiMdamtpxv+ZyR71lmTcTzQHA6GgZui5iPeo57iHPIyMelZiHC4zT0ZguOMVPOAmoKjNvVBjHpWNfGWMmWPGQ2V+lbTkuMECqk0KE9CcVcXcDmfEGpJdWxhn+9txkCuR2sjZI4rvda0eKaFm2DPoK46S0eO+WGXKozbQa2WhMloTeF72OG+CTlmQsNy+or1bRdc0uysg8kUUIK4T1Nec/8ACH34fz7YNIr4II7Cuo8A+Fmn1ArrjOkCn5Nw61cIp7mDVmdGPGlu4EdtDJJjqyqTXReH9XN4mPs8igDkspFaOn2Hhyzth9ltEyuM4j61owazpcaCFbJMng4j5NVKCWoJ2KyyqyBs9aXePSp7+2Kwm6MflxMflB61VV4yMl8A9Kx0ZXtGKxzUi8LzTEZMkhwR60qsCThgwrJxVyW7sUkunFIFIIPvUgbjGBimSPzxjpWkJLYSuf/Z
