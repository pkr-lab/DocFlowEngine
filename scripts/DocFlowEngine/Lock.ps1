# Lock-Mechanismus für den Multi-Machine-Betrieb (siehe MULTI-MACHINE-SETUP.md,
# Baustein 3). Verhindert, dass zwei Rechner gleichzeitig in dieselbe geteilte
# State-/Registry-Datei schreiben. Bewusst nur mit PowerShell-5.1-Bordmitteln
# umgesetzt (Test-Path/Get-Content/Set-Content/Remove-Item), kein Mutex.

function Test-DocFlowLockFresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LockPath,
        [Parameter(Mandatory)] [int]$TimeoutMinutes
    )

    if (-not (Test-Path $LockPath)) {
        return $false
    }

    # -Force nötig, da Dateien mit führendem Punkt (wie ".docflow-lock") auf
    # macOS/Linux von PowerShells FileSystem-Provider standardmäßig als
    # versteckt gelten und von Get-Item sonst nicht gefunden werden, obwohl
    # Test-Path sie sieht.
    $age = (Get-Date) - (Get-Item -Path $LockPath -Force).LastWriteTime
    return ($age.TotalMinutes -lt $TimeoutMinutes)
}

function Lock-DocFlowRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LockPath,
        [int]$TimeoutMinutes = 15
    )

    $lockDir = Split-Path -Path $LockPath -Parent
    if ($lockDir -and -not (Test-Path $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }

    if (Test-DocFlowLockFresh -LockPath $LockPath -TimeoutMinutes $TimeoutMinutes) {
        $existing = Get-Content -Path $LockPath -Raw -ErrorAction SilentlyContinue
        Write-Log -Level Warning -Message "Lauf abgebrochen: aktive Lock-Datei '$LockPath' gefunden ($existing)."
        return $false
    }

    $lockContent = "$([System.Environment]::MachineName)|$PID|$((Get-Date).ToString('o'))"
    Set-Content -Path $LockPath -Value $lockContent -Encoding UTF8
    return $true
}

function Unlock-DocFlowRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LockPath
    )

    if (Test-Path $LockPath) {
        Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue
    }
}
