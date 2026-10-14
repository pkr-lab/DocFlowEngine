function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Trace','Debug','Info','Warning','Error')] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    if (-not $Script:LogLevels) {
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

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    $resolved = $null
    try {
        $resolved = Resolve-Path -Path $PathValue -ErrorAction Stop
    } catch {
        $resolved = $null
    }

    if ($resolved) {
        return $resolved.ProviderPath
    }

    if ($PathValue -match '[*?]') {
        $trailingSegments = New-Object System.Collections.Generic.List[string]
        $current = $PathValue.TrimEnd('\', '/')

        while ($true) {
            $parent = Split-Path -Path $current -Parent
            $leaf = Split-Path -Path $current -Leaf
            if (-not $parent -or $parent -eq $current) {
                break
            }

            $trailingSegments.Insert(0, $leaf)
            $current = $parent

            try {
                $resolvedParent = Resolve-Path -Path $current -ErrorAction Stop
                $result = $resolvedParent.ProviderPath
                foreach ($segment in $trailingSegments) {
                    $result = Join-Path $result $segment
                }
                return $result
            } catch {
                continue
            }
        }

        throw "Pfad '$PathValue' enthält Wildcards, aber es konnte kein existierendes übergeordnetes Verzeichnis dafür gefunden werden."
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $PathValue))
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

function ConvertTo-DocFlowHashtable {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-DocFlowHashtable -InputObject $property.Value
            }
            return $hash
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            return @($InputObject | ForEach-Object { ConvertTo-DocFlowHashtable -InputObject $_ })
        }

        return $InputObject
    }
}

function Get-DocFlowRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string]$FullPath
    )

    $normalizedBase = $BasePath.TrimEnd('\', '/')
    if ($FullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $FullPath.Substring($normalizedBase.Length).TrimStart('\', '/')
    } else {
        $relative = $FullPath
    }

    return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Replace('\', [System.IO.Path]::DirectorySeparatorChar)
}

function Copy-DocFlowFileWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination,
        [int]$RetryCount = 2,
        [int]$RetryDelaySeconds = 5
    )

    $attempts = [Math]::Max(0, $RetryCount) + 1
    $lastError = $null

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
            $sourceLength = (Get-Item -LiteralPath $Source -Force -ErrorAction Stop).Length
            $destinationItem = Get-Item -LiteralPath $Destination -Force -ErrorAction Stop
            if ($destinationItem.Length -ne $sourceLength) {
                throw "Zieldatei hat $($destinationItem.Length) Bytes, Quelle $sourceLength Bytes."
            }
            return $true
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $attempts) {
                Write-Log -Level Warning -Message "Kopierversuch $attempt von $attempts fehlgeschlagen: '$Source' -> '$Destination' ($lastError). Neuer Versuch in $RetryDelaySeconds Sekunden."
                if ($RetryDelaySeconds -gt 0) {
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
        }
    }

    Write-Log -Level Error -Message "Kopieren nach $attempts Versuchen fehlgeschlagen: '$Source' -> '$Destination' ($lastError). Wird beim nächsten Lauf erneut versucht."
    return $false
}

function Test-DocFlowFileReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [double]$MinAgeMinutes = 0
    )

    if ($MinAgeMinutes -gt 0) {
        $age = (Get-Date).ToUniversalTime() - $File.LastWriteTimeUtc
        if ($age.TotalMinutes -lt $MinAgeMinutes) {
            Write-Log -Level Info -Message "Datei '$($File.Name)' wurde vor weniger als $MinAgeMinutes Minuten geändert und wird evtl. noch geschrieben/synchronisiert. Verarbeitung im nächsten Lauf."
            return $false
        }
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $true
    } catch {
        Write-Log -Level Info -Message "Datei '$($File.Name)' ist gerade gesperrt (wird noch geschrieben/synchronisiert). Verarbeitung im nächsten Lauf."
        return $false
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Write-DocFlowHintFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Content,
        [Parameter(Mandatory)] [string]$LogMessage
    )

    if (Test-Path -LiteralPath $Path) {
        return
    }

    if ($Script:DryRun) {
        Write-Log -Level Warning -Message "[DryRun] $LogMessage Hinweis-Datei würde erstellt: '$Path'"
        return
    }

    try {
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8 -ErrorAction Stop
        Write-Log -Level Warning -Message "$LogMessage Hinweis-Datei erstellt: '$Path'"
    } catch {
        Write-Log -Level Error -Message "$LogMessage Hinweis-Datei konnte nicht erstellt werden: '$Path' ($($_.Exception.Message))"
    }
}

function Remove-DocFlowHintFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Reason
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if ($Script:DryRun) {
        Write-Log -Level Info -Message "[DryRun] Hinweis-Datei würde entfernt ($Reason): '$Path'"
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log -Level Info -Message "Hinweis-Datei entfernt ($Reason): '$Path'"
    } catch {
        Write-Log -Level Warning -Message "Hinweis-Datei konnte nicht entfernt werden: '$Path' ($($_.Exception.Message))"
    }
}

function Remove-DocFlowOrphanedHintFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Directory,
        [Parameter(Mandatory)] [string[]]$HintSuffixes,
        [bool]$Recurse = $true
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return
    }

    foreach ($suffix in $HintSuffixes) {
        if (-not $suffix) {
            continue
        }

        $hintFiles = Get-ChildItem -LiteralPath $Directory -File -Recurse:$Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase) }
        foreach ($hintFile in $hintFiles) {
            $originalName = $hintFile.Name.Substring(0, $hintFile.Name.Length - $suffix.Length)
            if (-not $originalName) {
                continue
            }

            $originalPath = Join-Path $hintFile.DirectoryName $originalName
            if (-not (Test-Path -LiteralPath $originalPath)) {
                Remove-DocFlowHintFile -Path $hintFile.FullName -Reason "Datei '$originalName' existiert nicht mehr"
            }
        }
    }
}
