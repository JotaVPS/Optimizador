# ================================
# UNA SOLA INSTANCIA
# ================================
# Si ya está abierto (por ejemplo en la bandeja), le avisa que se muestre y se cierra.

if (-not $Accion -and -not $Captura -and -not $Desinstalar) {
    $creado = $false
    try { $script:Mutex = New-Object Threading.Mutex($true, 'Local\OptimizadorJvps', [ref]$creado) } catch { $creado = $false }
    if (-not $creado) {
        try { [void][Threading.EventWaitHandle]::OpenExisting('Local\OptimizadorJvps_Mostrar').Set() } catch { }
        exit
    }
}

