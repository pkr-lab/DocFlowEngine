function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Trace','Debug','Info','Warning','Error')] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    if (-not $Script:LogLevelsw) {
        $Script:LogLevels = @{ TRACE = 0; DEBUG = 1; INFO = 2; WARNING = 3; ERROR = 4 }
    }

    if ($null -eq $Script:CurrentLogLevel) {
        $Script:CurrentLogLevel = $Script:LogLevels['INFO']
    }

    $level = $Level.ToUpperInvariant()
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if (-not $Script:LogLevels.ContainsKey($level)) {
        $level = 'INFO'
    }

    if ($Script:CurrentLogLevel -le $Script:LogLevels[$level]) {
        $output = "[$timestamp] [$level] $Message"
        Write-Host $output
        if ($Script:LogFilePath) {
            Add-Content -Path $Script:LogFilePath -Value $output
        }
    }
}

function Expand-Template {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Template,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    $result = $Template
    foreach ($key in $Context.Keys) {
        $result = $result.Replace("{$key}", [string]$Context[$key])
    }

    return $result
}

function Resolve-PathOrAbsolute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PathValue
    )

    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        $resolved = $null
        try {
            $resolved = Resolve-Path -Path $PathValue -ErrorAction Stop
        } catch {
            $resolved = $null
        }

        if ($resolved) {
            return $resolved.ProviderPath
        }

        if ([System.IO.Path]::IsPathRooted($PathValue)) {
            return [System.IO.Path]::GetFullPath($PathValue)
        }

        return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $PathValue))
    }

    return $null
}

function Resolve-SourcePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PathValue
    )

    try {
        $items = Resolve-Path -Path $PathValue -ErrorAction Stop
        return @($items | ForEach-Object { $_.ProviderPath })
    } catch {
        return @()
    }
}

function Test-PathExcluded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FullName,
        [array]$ExcludePaths = @()
    )

    foreach ($exclude in $ExcludePaths) {
        if (-not $exclude) {
            continue
        }

        $normalizedExclude = $exclude.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($FullName.StartsWith($normalizedExclude, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}