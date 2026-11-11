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
