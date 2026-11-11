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

