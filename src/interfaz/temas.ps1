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

