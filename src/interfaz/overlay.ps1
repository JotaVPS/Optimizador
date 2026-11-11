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

