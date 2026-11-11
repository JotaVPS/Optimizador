    # ---------- PUNTO DE RESTAURACIÓN (antes de Red y Reparar) ----------
    function Crear-PuntoRestauracion($motivo, [int]$pct = 2) {
        Set-Prog $pct 'Creando punto de restauración'
        Out-Line '  Creando punto de restauración de Windows (puede tardar un minuto)...' 'dim'
        $antes = @(Get-ComputerRestorePoint).Count
        $error_ = $null
        try { Checkpoint-Computer -Description "Optimizador J.vps: antes de $motivo" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue }
        catch { $error_ = $_.Exception.Message }
        if (@(Get-ComputerRestorePoint).Count -gt $antes) {
            Out-Line '  Punto de restauración creado: si algo sale mal, Inicio > "Recuperación" > Abrir Restaurar sistema.' 'ok'
        } elseif ($error_) {
            # casi siempre: la Protección del sistema está apagada en C:
            Out-Line '  No se pudo crear el punto de restauración (¿Protección del sistema apagada en C:?). Se sigue igual.' 'warn'
        } else {
            # Windows hace como mucho uno por día: si ya hubo uno, usa ese
            Out-Line '  Windows ya tiene un punto de restauración de hoy: se usa ese.' 'dim'
        }
    }

