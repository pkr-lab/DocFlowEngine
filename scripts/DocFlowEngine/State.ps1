function Load-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StatePath
    )

    if (-not (Test-Path $StatePath)) {
        return @{ processed = @{}; reviewedFiles = @{} }
    }

    try {
        $json = Get-Content -Path $StatePath -Raw
        $parsed = $json | ConvertFrom-Json
        $state = ConvertTo-DocFlowHashtable -InputObject $parsed
        if (-not $state.ContainsKey('processed')) {
            $state.processed = @{}
        }
        if (-not $state.ContainsKey('reviewedFiles')) {
            $state.reviewedFiles = @{}
        }
        return $state
    } catch {
        Write-Log -Level Warning -Message "Zustandsdatei '$StatePath' konnte nicht gelesen werden. Es wird eine neue Datei erstellt."
        return @{ processed = @{}; reviewedFiles = @{} }
    }
}

function Save-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StatePath,
        [Parameter(Mandatory)] [hashtable]$State
    )

    $directory = Split-Path -Path $StatePath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}
