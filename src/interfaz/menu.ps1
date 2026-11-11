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

