function Test-DocFlowLockFresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LockPath,
        [Parameter(Mandatory)] [int]$TimeoutMinutes
    )

    if (-not (Test-Path $LockPath)) {
        return $false
    }

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
