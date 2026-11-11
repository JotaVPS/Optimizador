# ================================
# NUCLEO (corre en segundo plano para no congelar la ventana)
# ================================

# ---------- programas de consola sin ventana ----------
# Optimizador.exe no tiene consola: cada powercfg, netsh o nvidia-smi llamado con & abría una ventana negra
# que además le sacaba el foco al juego (Roblox se trababa con la pestaña Rendimiento abierta). Todo lo de
# consola pasa por acá: sin ventana y con la salida en el idioma de la consola (acentos bien).
if (-not ('JVps.Consola' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Globalization; using System.IO; using System.Text;
using System.Net; using System.Net.NetworkInformation; using System.Net.Sockets; using System.Security.Cryptography; using System.Text.RegularExpressions;
namespace JVps {
public static class Consola {
    static Process Nuevo(string exe, string args) {
        var oem = Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
        var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
            RedirectStandardError = true, RedirectStandardInput = true, StandardOutputEncoding = oem, StandardErrorEncoding = oem };
        var p = Process.Start(psi);
        p.StandardInput.Close();   // si algo pregunta (takeown), no se queda esperando
        return p;
    }
    // corre y devuelve lo que escribió (salida y errores); msMax -1 = sin límite
    public static string[] Correr(string exe, string args, int msMax) {
        try {
            using (var p = Nuevo(exe, args)) {
                var salida = p.StandardOutput.ReadToEndAsync(); var errores = p.StandardError.ReadToEndAsync();
                if (!p.WaitForExit(msMax < 0 ? int.MaxValue : msMax)) { try { p.Kill(); } catch { } }
                salida.Wait(3000); errores.Wait(3000);
                string t = (salida.IsCompleted ? salida.Result : "") + (errores.IsCompleted ? errores.Result : "");
                return t.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
            }
        } catch { return new string[0]; }
    }
    public static string[] Correr(string exe, string args) { return Correr(exe, args, 60000); }
    // para los largos (DISM, SFC): el proceso abierto, para leer el progreso renglón por renglón
    public static Process Abrir(string exe, string args) {
        var p = Nuevo(exe, args);
        p.StandardError.ReadToEndAsync();
        return p;
    }
}

// router Movistar Fibra (Askey / Mitrastar, firmware Broadcom): entrar con la contraseña de la etiqueta y reiniciarlo.
// El login es base64("admin:" + md5(sid + ":" + clave)), igual que la página; el reinicio es rebootinfo.cgi con
// la clave de sesión que trae resetrouter.html. Registro junta lo que pasó (sin contraseñas) por si un modelo no anda.
public class Router {
    public readonly string Ip;
    public readonly List<string> Registro = new List<string>();
    readonly CookieContainer galletas = new CookieContainer();
    public Router(string ip) { Ip = ip; }
    class Resp { public int Codigo; public string Texto = ""; public string Destino = ""; }

    Resp Pedir(string ruta, string post, int ms) {
        var r = new Resp();
        var req = (HttpWebRequest)WebRequest.Create("http://" + Ip + ruta);
        req.CookieContainer = galletas; req.AllowAutoRedirect = false; req.Proxy = null;
        req.Timeout = ms; req.ReadWriteTimeout = ms;
        req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"; req.Referer = "http://" + Ip + "/";
        if (post != null) {
            req.Method = "POST"; req.ContentType = "application/x-www-form-urlencoded";
            var b = Encoding.ASCII.GetBytes(post); req.ContentLength = b.Length;
            using (var st = req.GetRequestStream()) st.Write(b, 0, b.Length);
        }
        HttpWebResponse resp;
        try { resp = (HttpWebResponse)req.GetResponse(); }
        catch (WebException e) { resp = e.Response as HttpWebResponse; if (resp == null) throw; }
        using (resp) {
            r.Codigo = (int)resp.StatusCode;
            r.Destino = resp.Headers["Location"] ?? "";
            using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) r.Texto = sr.ReadToEnd();
        }
        if (r.Destino == "" && r.Texto.Length < 600) {   // redirige con javascript: top.location='...'
            var m = Regex.Match(r.Texto, @"(?:top|window)\.location(?:\.href)?\s*=\s*['""]([^'""]+)['""]");
            if (m.Success) r.Destino = m.Groups[1].Value;
        }
        return r;
    }
    static bool EsLogin(Resp r) {
        return r.Codigo == 401 || r.Texto.Contains("passWarning") || r.Destino.IndexOf("logIn", StringComparison.OrdinalIgnoreCase) >= 0;
    }
    static string Md5(string s) {
        var sb = new StringBuilder();
        using (var md5 = MD5.Create()) foreach (var b in md5.ComputeHash(Encoding.GetEncoding(28591).GetBytes(s))) sb.Append(b.ToString("x2"));
        return sb.ToString();
    }
    void Log(string t) { Registro.Add(Regex.Replace(t, @"(sessionKey\s*[=:]\s*'?)\w+", m => m.Groups[1].Value + "...")); }

    // la página de inicio del router es la del Movistar Fibra
    public static bool Compatible(string html) {
        return html != null && html.Contains("login-login.cgi") && Regex.IsMatch(html, @"var\s+sid\s*=");
    }

    // null = entró; si no, el motivo
    public string Entrar(string clave) {
        var ini = Pedir("/", null, 8000);
        var sid = Regex.Match(ini.Texto, @"var\s+sid\s*=\s*""([^""]+)""");
        if (!sid.Success) { Log("sin página de login (código " + ini.Codigo + ")"); return "La página del router no es la de un Movistar Fibra"; }
        string usuario = Regex.IsMatch(ini.Texto, @"var\s+supportArgentina\s*=\s*'1'") ? "admin" : "Support";
        string k = Convert.ToBase64String(Encoding.GetEncoding(28591).GetBytes(usuario + ":" + Md5(sid.Groups[1].Value + ":" + clave)));
        var r = Pedir("/login-login.cgi", "sessionKey=" + Uri.EscapeDataString(k) + "&pass=", 10000);
        Log("login: código " + r.Codigo + ", destino " + r.Destino);
        return EsLogin(r) ? "Contraseña incorrecta" : null;
    }

    // la dirección para reiniciar este modelo, o null si no la encuentra
    public string BuscarReinicio() {
        foreach (var pagina in new[] { "/resetrouter.html", "/resetrouter.htm", "/reboot.html" }) {
            Resp p;
            try { p = Pedir(pagina, null, 8000); } catch (Exception e) { Log(pagina + ": " + e.Message); continue; }
            Log(pagina + ": código " + p.Codigo + ", " + p.Texto.Length + " bytes");
            if (p.Codigo != 200 || EsLogin(p)) continue;
            var clave = Regex.Match(p.Texto, @"sessionKey\s*[=:]\s*['""]?(\w+)");
            var accion = Regex.Match(p.Texto, @"(\w*reboot\w*\.(?:cgi|cmd))", RegexOptions.IgnoreCase);
            return "/" + (accion.Success ? accion.Groups[1].Value : "rebootinfo.cgi") + (clave.Success ? "?sessionKey=" + clave.Groups[1].Value : "");
        }
        return null;
    }

    // true si aceptó la orden (o cortó porque ya se está apagando)
    public bool Reiniciar(string ruta) {
        try {
            var r = Pedir(ruta, null, 8000);
            Log("reinicio: código " + r.Codigo);
            return r.Codigo == 200 && !EsLogin(r);
        } catch (WebException e) { Log("reinicio: se cortó (" + e.Status + ")"); return true; }
    }

    // puerta de enlace de la conexión activa
    public static string Puerta() {
        try {
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) {
                if (n.OperationalStatus != OperationalStatus.Up || n.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var g in n.GetIPProperties().GatewayAddresses)
                    if (g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)) return g.Address.ToString();
            }
        } catch { }
        return null;
    }
}
}
"@
}
