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
        # Pfad enthält Wildcards (z. B. geräteabhängige OneDrive-Ordnernamen) und
        # existiert als Ganzes noch nicht (z. B. weil ein Zielordner erst von
        # DocFlowEngine angelegt wird). Wir schneiden vom Ende her Segmente ab,
        # bis ein existierendes (ggf. ebenfalls wildcardhaltiges) Elternverzeichnis
        # gefunden und via Resolve-Path aufgelöst werden kann, und hängen die
        # fehlenden Segmente danach wieder literal an.
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
            # Bewusst @{} statt [ordered]@{}: Eine OrderedDictionary hat kein
            # ContainsKey (nur Contains), aber Copy-NewFiles ruft auf $State.processed
            # gezielt .ContainsKey() auf. Eine normale Hashtable verhält sich hier
            # wie das Original von ConvertFrom-Json -AsHashtable.
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

    # Bewusst reine String-Verarbeitung statt [Uri]::MakeRelativeUri: Ein
    # POSIX-Pfad wie "/tmp/..." (Linux/macOS mit PowerShell 7+) wird von .NET
    # ohne "file://"-Schema nicht als absolute URI erkannt und würde dort eine
    # Exception auslösen - anders als ein Windows-Pfad mit Laufwerksbuchstaben.
    # Damit funktioniert die Funktion auf allen laut README unterstützten
    # Plattformen gleich.
    $normalizedBase = $BasePath.TrimEnd('\', '/')
    if ($FullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $FullPath.Substring($normalizedBase.Length).TrimStart('\', '/')
    } else {
        $relative = $FullPath
    }

    return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Replace('\', [System.IO.Path]::DirectorySeparatorChar)
}
