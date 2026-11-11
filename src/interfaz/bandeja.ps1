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

