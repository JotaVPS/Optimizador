# ================================
# ADMIN
# ================================

$EsAdminAhora = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# desde el .exe no se vuelve a pedir: si cancelaron su aviso, abre con las opciones de admin limitadas
if (-not $EsAdminAhora -and -not $Accion -and -not $Captura -and -not $SinElevar) {
    # Suelta el mutex antes de relanzar, si no la copia elevada se creería la segunda instancia.
    $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose()
    if (Test-InstaladoAlDia) {
        # instalado: se abre con la tarea, sin aviso de permisos
        # si Windows no deja lanzarla, sigue por el camino de pedir permisos
        try { Start-ScheduledTask -TaskName $TareaNombre -ErrorAction Stop; exit } catch { }
    }
    # no instalado (o este archivo es una versión distinta): pide permisos una vez, directo desde PowerShell oculto
    try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList (Comando-Lanzar $Archivo); exit } catch { }
    # si cancelan el aviso abre igual, con las opciones de admin limitadas
    $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps')
}

