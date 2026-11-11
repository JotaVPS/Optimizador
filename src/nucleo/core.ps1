$Core = {
    $ErrorActionPreference = 'SilentlyContinue'
    $EsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    #incluir acciones/base.ps1
    #incluir acciones/limpieza.ps1
    #incluir acciones/juego.ps1
    #incluir acciones/restauracion.ps1
    #incluir acciones/diagnostico.ps1
    #incluir acciones/reparar.ps1
    #incluir acciones/red.ps1
    #incluir acciones/router.ps1
    function Invoke-Accion($a) {
        switch ($a) {
            'limpieza'    { Hacer-Limpieza }
            'juego'       { Hacer-ModoJuego }
            'todo'        {
                Hacer-Limpieza; Out-Line ''; Hacer-ModoJuego; Out-Line ''
                if ($EsAdmin) { Hacer-AjustesJuego; Out-Line '' } else { Out-Line '  Plan de energía y Game Bar: necesitan permisos de administrador.' 'warn'; Out-Line '' }
                Out-Line 'Sistema listo para jugar' 'title'
            }
            'diagnostico' { Hacer-Diagnostico; Hacer-Puntaje }   # "Revisión completa"
            'reparar'     { Hacer-Reparar }
            'red'         { Hacer-Red }
            'router'      { Hacer-ReiniciarRouter $false }
            'routerprobar' { Hacer-ReiniciarRouter $true }
            'restaurar'   { Hacer-Restaurar }
            # modo juego automático: al abrir un juego de la lista / al cerrarlo
            'autojuego'   { Hacer-ModoJuego; if ($EsAdmin) { Out-Line ''; Hacer-AjustesJuego } }
            'finjuego'    {
                Out-Line 'FIN DEL MODO JUEGO' 'title'
                if (Restaurar-Juego) { Out-Line '  Plan de energía y Game Bar: como estaban antes del juego.' 'ok' }
                else { Out-Line '  No había nada para volver atrás.' 'dim' }
            }
        }
        Set-Prog 100 'Listo'
    }
}
