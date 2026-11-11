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

