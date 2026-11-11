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

