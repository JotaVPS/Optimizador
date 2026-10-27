// Optimizador.exe: lanzador del Optimizador.bat
// Lleva el .bat adentro como recurso y lo corre con el PowerShell que trae Windows como librería,
// dentro de este mismo proceso: no se abre powershell.exe, ni consolas, ni hace falta -ExecutionPolicy Bypass
// (un PowerShell escondido con Bypass es lo que los antivirus marcan como sospechoso).
// Pide permisos con su propio nombre e ícono, no como "Windows PowerShell".
//   Optimizador.exe             uso normal (doble clic / acceso directo)
//   Optimizador.exe --directo   lo usa la tarea programada: corre la copia de Archivos de programa
//   Optimizador.exe --elevado   interno: no vuelve a pedir permisos ni a buscar otra ventana abierta
//                               (lo usa la copia con permisos y el reinicio después de actualizar)
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

static class Lanzador
{
    const string Tarea = "Optimizador J.vps";
    static readonly string Yo = Assembly.GetExecutingAssembly().Location;
    static readonly string InstBat = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Optimizador J.vps", "Optimizador.bat");
    // la copia de trabajo: si el programa se actualiza desde GitHub, la versión nueva queda acá
    static readonly string Datos = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Optimizador J.vps");
    static readonly string LocalBat = Path.Combine(Datos, "app", "Optimizador.bat");

    [STAThread]
    static void Main(string[] args)
    {
        bool directo = Array.IndexOf(args, "--directo") >= 0;
        bool elevado = Array.IndexOf(args, "--elevado") >= 0;

        if (directo) { Correr(InstBat); Environment.Exit(0); }

        // ya está abierto (por ejemplo en la bandeja): le avisa que se muestre, sin pedir permisos de nuevo
        if (!elevado)
            try { using (var e = EventWaitHandle.OpenExisting(@"Local\OptimizadorJvps_Mostrar")) { e.Set(); return; } } catch { }

        Extraer();
        if (!elevado && !EsAdmin())
        {
            // instalado y al día: la tarea lo abre con permisos sin el aviso de Windows
            if (Version(InstBat) >= Version(LocalBat) && Ejecutar("schtasks.exe", "/run /tn \"" + Tarea + "\"") == 0) return;
            try
            {
                Process.Start(new ProcessStartInfo(Yo, "--elevado") { UseShellExecute = true, Verb = "runas" });
                return;
            }
            catch (Win32Exception) { }   // cancelaron el aviso: abre igual, con las opciones de admin limitadas
        }
        Correr(LocalBat);
        // los hilos de fondo del script (medición de datos, bandeja) no tienen que dejar el proceso vivo
        Environment.Exit(0);
    }

    // escribe el .bat de adentro en LocalAppData, salvo que ahí ya haya uno más nuevo (bajado de GitHub)
    static void Extraer()
    {
        byte[] bat;
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Optimizador.bat"))
        using (var m = new MemoryStream()) { s.CopyTo(m); bat = m.ToArray(); }
        if (File.Exists(LocalBat) && Version(LocalBat) > VersionDe(Encoding.UTF8.GetString(bat))) return;
        Directory.CreateDirectory(Path.GetDirectoryName(LocalBat));
        File.WriteAllBytes(LocalBat, bat);
    }

    // corre el programa en este hilo (STA, como pide WPF) hasta que se cierra la ventana
    static void Correr(string bat)
    {
        try
        {
            var iss = InitialSessionState.CreateDefault();
            // RemoteSigned: deja cargar los módulos firmados de Windows (tareas programadas, etc.)
            // aunque la PC tenga la política en Restricted, que es lo que viene de fábrica
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.RemoteSigned;
            using (var rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                rs.SessionStateProxy.SetVariable("Archivo", bat);
                // el script lo lee como $env:OptimizadorExe para instalar este .exe y relanzarse con él
                Environment.SetEnvironmentVariable("OptimizadorExe", Yo);
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    // -SinElevar: los permisos los pide este .exe, el script no se relanza como PowerShell
                    ps.AddScript(File.ReadAllText(bat, Encoding.UTF8)).AddParameter("SinElevar");
                    ps.Invoke();
                }
            }
        }
        catch (ExitException) { }   // el script terminó con exit
        catch (Exception ex) { Log(ex.ToString()); }
    }

    // el script corre con $ErrorActionPreference = SilentlyContinue: acá solo llega lo que lo tumbó
    static void Log(string texto)
    {
        try
        {
            Directory.CreateDirectory(Datos);
            File.AppendAllText(Path.Combine(Datos, "lanzador.log"), DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + texto + Environment.NewLine);
        }
        catch { }
    }

    static int Ejecutar(string exe, string argumentos)
    {
        try
        {
            using (var p = Process.Start(new ProcessStartInfo(exe, argumentos) { UseShellExecute = false, CreateNoWindow = true }))
            {
                p.WaitForExit(10000);
                return p.HasExited ? p.ExitCode : -1;
            }
        }
        catch { return -1; }
    }

    static bool EsAdmin()
    {
        return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
    }

    // la línea $Version = '...' del .bat (igual que Get-VersionArchivo)
    static Version Version(string ruta)
    {
        if (!File.Exists(ruta)) return new Version(0, 0);
        try
        {
            var sb = new StringBuilder();
            using (var r = new StreamReader(ruta, Encoding.UTF8))
                for (int i = 0; i < 40 && !r.EndOfStream; i++) sb.AppendLine(r.ReadLine());
            return VersionDe(sb.ToString());
        }
        catch { return new Version(0, 0); }
    }

    static Version VersionDe(string texto)
    {
        var m = Regex.Match(texto, @"\$Version = '([\d.]+)'");
        return m.Success ? new Version(m.Groups[1].Value) : new Version(0, 0);
    }
}
