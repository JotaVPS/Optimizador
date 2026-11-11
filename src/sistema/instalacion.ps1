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

