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

function Load-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Konfigurationsdatei '$Path' wurde nicht gefunden."
    }

    $yaml = Get-Content -Path $Path -Raw
    $config = $yaml | ConvertFrom-Yaml

    if (-not $config.sources) {
        throw "Konfiguration muss mindestens einen Eintrag unter 'sources' enthalten."
    }

    if (-not $config.targets) {
        throw "Konfiguration muss mindestens einen Eintrag unter 'targets' enthalten."
    }

    if (-not $config.namingConventions) {
        throw "Konfiguration muss mindestens eine Regel unter 'namingConventions' enthalten."
    }

    if (-not $config.stateFile) {
        $config | Add-Member -NotePropertyName stateFile -NotePropertyValue './.docflow-state.json'
    }

    if (-not $config.log) {
        $config | Add-Member -NotePropertyName log -NotePropertyValue @{ level = 'Info'; file = './docflow.log' }
    }

    return $config
}

function Load-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StatePath
    )

    if (-not (Test-Path $StatePath)) {
        return [ordered]@{ processed = @{} }
    }

    try {
        $json = Get-Content -Path $StatePath -Raw
        return $json | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Log -Level Warning -Message "Zustandsdatei '$StatePath' konnte nicht gelesen werden. Es wird eine neue Datei erstellt."
        return [ordered]@{ processed = @{} }
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

function Ensure-TargetDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Targets
    )

    foreach ($target in $Targets) {
        $targetPath = Resolve-PathOrAbsolute -PathValue $target.path
        if (-not (Test-Path $targetPath)) {
            if ($target.createIfMissing -eq $false) {
                throw "Zielverzeichnis '$($target.path)' existiert nicht und createIfMissing ist false."
            }

            if ($Script:DryRun) {
                Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $targetPath"
            } else {
                Write-Log -Level Info -Message "Erstelle Zielverzeichnis: $targetPath"
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }
        }

        $target.path = $targetPath
    }
}

function Get-SourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] [string]$ResolvedPath
    )

    if (-not (Test-Path $ResolvedPath)) {
        Write-Log -Level Warning -Message "Quellverzeichnis '$ResolvedPath' existiert nicht. Überspringe."
        return @()
    }

    $files = [ordered]@{}
    foreach ($pattern in $Source.includePatterns) {
        if ($Source.recursive) {
            $items = Get-ChildItem -Path $ResolvedPath -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue
        } else {
            $items = Get-ChildItem -Path $ResolvedPath -Filter $pattern -File -ErrorAction SilentlyContinue
        }

        foreach ($item in $items) {
            $files[$item.FullName] = $item
        }
    }

    return $files.Values
}

function Get-TargetFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules,
        [Parameter(Mandatory)] [string]$DefaultFormat
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $extension = [System.IO.Path]::GetExtension($File.Name).TrimStart('.')
    $context = [ordered]@{
        originalName = $originalName
        extension = $extension
        timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
        date = (Get-Date).ToString('yyyyMMdd')
    }

    foreach ($rule in $Rules) {
        if ($originalName -match $rule.match) {
            foreach ($groupName in $Matches.Keys) {
                if ($groupName -ne '0') {
                    $context[$groupName] = $Matches[$groupName]
                }
            }

            $targetName = Expand-Template -Template $rule.rename -Context $context
            if (-not $targetName) {
                continue
            }

            if (-not $targetName.EndsWith(".$extension", [System.StringComparison]::InvariantCultureIgnoreCase)) {
                $targetName = "$targetName.$extension"
            }

            return $targetName
        }
    }

    if (-not $DefaultFormat) {
        $DefaultFormat = '{timestamp}_{originalName}'
    }

    $fallbackName = Expand-Template -Template $DefaultFormat -Context $context
    if (-not $fallbackName.EndsWith(".$extension", [System.StringComparison]::InvariantCultureIgnoreCase)) {
        $fallbackName = "$fallbackName.$extension"
    }

    return $fallbackName
}

function Get-FileCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

    foreach ($rule in $Rules) {
        if ($originalName -match $rule.match) {
            $matchResult = $Matches
            if ($matchResult.ContainsKey('project') -and $matchResult.project -match '^[A-Za-z]+') {
                return $Matches[0]
            }
        }
    }

    return $null
}

function Resolve-CategoryTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LeadingLetters,
        [Parameter(Mandatory)] [array]$CategoryRoutes
    )

    foreach ($route in $CategoryRoutes) {
        if ($LeadingLetters.StartsWith($route.category, [System.StringComparison]::InvariantCultureIgnoreCase)) {
            return $route.target
        }
    }

    return $null
}

function Get-FileProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

    foreach ($rule in $Rules) {
        if ($originalName -match $rule.match) {
            if ($Matches.ContainsKey('project')) {
                return $Matches.project
            }
        }
    }

    return $null
}

function Get-FilePraefixSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

    foreach ($rule in $Rules) {
        if ($originalName -match $rule.match) {
            if ($Matches.ContainsKey('praefix') -and $Matches.ContainsKey('suffix')) {
                return [PSCustomObject]@{ Praefix = $Matches.praefix; Suffix = $Matches.suffix }
            }
        }
    }

    return $null
}

function Get-PraefixSuffixRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $registry = [ordered]@{
        Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Suffixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    if (-not (Test-Path $Path)) {
        Write-Log -Level Warning -Message "Registry-Datei '$Path' wurde nicht gefunden."
        return $registry
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $trimmed.Substring(0, $separatorIndex).Trim().ToLowerInvariant()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if (-not $value) {
            continue
        }

        if ($key -eq 'praefix') {
            [void]$registry.Praefixe.Add($value)
        } elseif ($key -eq 'suffix') {
            [void]$registry.Suffixe.Add($value)
        }
    }

    return $registry
}

function Register-PraefixSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Registry,
        [string]$RegistryFilePath,
        [Parameter(Mandatory)] [string]$Praefix,
        [Parameter(Mandatory)] [string]$Suffix
    )

    $newLines = @()

    if (-not $Registry.Praefixe.Contains($Praefix)) {
        [void]$Registry.Praefixe.Add($Praefix)
        $newLines += "praefix=$Praefix"
        Write-Log -Level Info -Message "Neuer Präfix erkannt und in Registry aufgenommen: '$Praefix'"
    }

    if (-not $Registry.Suffixe.Contains($Suffix)) {
        [void]$Registry.Suffixe.Add($Suffix)
        $newLines += "suffix=$Suffix"
        Write-Log -Level Info -Message "Neuer Suffix erkannt und in Registry aufgenommen: '$Suffix'"
    }

    if ($newLines.Count -gt 0 -and $RegistryFilePath) {
        if ($Script:DryRun) {
            Write-Log -Level Info -Message "[DryRun] Registry-Datei '$RegistryFilePath' würde aktualisiert: $($newLines -join ', ')"
        } else {
            Add-Content -Path $RegistryFilePath -Value $newLines
        }
    }
}

function Get-ProjectRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $routes = @{}

    if (-not (Test-Path $Path)) {
        Write-Log -Level Warning -Message "Projekt-Routing-Datei '$Path' wurde nicht gefunden."
        return $routes
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $projectName = $trimmed.Substring(0, $separatorIndex).Trim()
        $targetPath = $trimmed.Substring($separatorIndex + 1).Trim()
        if ($projectName -and $targetPath) {
            $routes[$projectName] = $targetPath
        }
    }

    return $routes
}

function Resolve-ProjectTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProjectName,
        [Parameter(Mandatory)] [hashtable]$ProjectRoutes
    )

    if ($ProjectRoutes.ContainsKey($ProjectName)) {
        return $ProjectRoutes[$ProjectName]
    }

    return $null
}

function Copy-NewFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Sources,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Targets,
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Rules,
        [Parameter(Mandatory)] [string]$DefaultNameFormat,
        [array]$CategoryRoutes = @(),
        [hashtable]$ProjectRoutes = @{},
        [string]$AufgabenRoot = $null,
        [hashtable]$PraefixSuffixRegistry = $null,
        [string]$RegistryFilePath = $null,
        [array]$ExcludePaths = @()
    )

    foreach ($source in $Sources) {
        $resolvedSourcePaths = Resolve-SourcePaths -PathValue $source.path
        if ($resolvedSourcePaths.Count -eq 0) {
            Write-Log -Level Warning -Message "Quellverzeichnis '$($source.path)' existiert nicht oder wurde nicht gefunden. Überspringe."
            continue
        }

        foreach ($resolvedSourcePath in $resolvedSourcePaths) {
            $items = Get-SourceFiles -Source $source -ResolvedPath $resolvedSourcePath
            Write-Log -Level Info -Message "Gefundene Dateien in '$resolvedSourcePath': $($items.Count)"

            foreach ($item in $items) {
                if (Test-PathExcluded -FullName $item.FullName -ExcludePaths $ExcludePaths) {
                    continue
                }

                $sourceKey = $item.FullName.ToLowerInvariant()
                if ($State.processed.ContainsKey($sourceKey)) {
                    continue
                }

                $targetFileName = Get-TargetFileName -File $item -Rules $Rules -DefaultFormat $DefaultNameFormat

                $effectiveTargets = $Targets
                $routingActive = ($ProjectRoutes.Count -gt 0) -or ($CategoryRoutes.Count -gt 0)
                $routedTargetPath = $null

                if ($AufgabenRoot) {
                    $praefixSuffix = Get-FilePraefixSuffix -File $item -Rules $Rules
                    if ($praefixSuffix) {
                        if ($PraefixSuffixRegistry) {
                            Register-PraefixSuffix -Registry $PraefixSuffixRegistry -RegistryFilePath $RegistryFilePath -Praefix $praefixSuffix.Praefix -Suffix $praefixSuffix.Suffix
                        }

                        $routedTargetPath = Join-Path (Join-Path $AufgabenRoot $praefixSuffix.Praefix) $praefixSuffix.Suffix
                    }
                }

                if (-not $routedTargetPath -and $ProjectRoutes.Count -gt 0) {
                    $projectName = Get-FileProject -File $item -Rules $Rules
                    if ($projectName) {
                        $routedTargetPath = Resolve-ProjectTarget -ProjectName $projectName -ProjectRoutes $ProjectRoutes
                    }
                }

                if (-not $routedTargetPath -and $CategoryRoutes.Count -gt 0) {
                    $leadingLetters = Get-FileCategory -File $item -Rules $Rules
                    if ($leadingLetters) {
                        $routedTargetPath = Resolve-CategoryTarget -LeadingLetters $leadingLetters -CategoryRoutes $CategoryRoutes
                    }
                }

                if ($routedTargetPath) {
                    $effectiveTargets = @(@{ path = (Resolve-PathOrAbsolute -PathValue $routedTargetPath); preserveSubfolders = $false })
                } elseif ($routingActive) {
                    Write-Log -Level Warning -Message "Keine passende Projekt- oder Kategorie-Zuordnung für '$($item.Name)' gefunden. Datei wird übersprungen."
                    continue
                }

                $targetPaths = @()

                foreach ($target in $effectiveTargets) {
                    $destinationDirectory = $target.path
                    if ($target.preserveSubfolders) {
                        $relative = [System.IO.Path]::GetRelativePath($resolvedSourcePath, $item.DirectoryName)
                        if ($relative -and $relative -ne '.') {
                            $destinationDirectory = Join-Path $destinationDirectory $relative
                        }
                    }

                    if (-not (Test-Path $destinationDirectory)) {
                        if ($Script:DryRun) {
                            Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $destinationDirectory"
                        } else {
                            Write-Log -Level Info -Message "Erstelle Verzeichnis: $destinationDirectory"
                            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                        }
                    }

                    $destinationPath = Join-Path $destinationDirectory $targetFileName
                    if ($Script:DryRun) {
                        Write-Log -Level Info -Message "[DryRun] Datei würde kopiert: '$($item.FullName)' -> '$destinationPath'"
                    } else {
                        Write-Log -Level Info -Message "Kopiere Datei: '$($item.FullName)' -> '$destinationPath'"
                        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
                    }

                    $targetPaths += $destinationPath
                }

                $State.processed[$sourceKey] = [ordered]@{
                    source = $item.FullName
                    targets = $targetPaths
                    processedAt = (Get-Date).ToString('o')
                }
            }
        }
    }
}

function Invoke-DocFlowEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigPath = '.\config\docflow-config.yml',
        [switch]$DryRun
    )

    $Script:LogLevels = @{ Trace = 0; Debug = 1; Info = 2; Warning = 3; Error = 4 }
    $Script:DryRun = $DryRun

    $config = Load-Config -Path $ConfigPath
    $logLevelName = ($config.log.level ?? 'Info').ToString()
    if (-not $Script:LogLevels.ContainsKey($logLevelName)) {
        $logLevelName = 'Info'
    }

    $Script:CurrentLogLevel = $Script:LogLevels[$logLevelName]
    $Script:LogFilePath = Resolve-PathOrAbsolute -PathValue $config.log.file

    if ($Script:LogFilePath -and -not $DryRun) {
        $logDir = Split-Path -Path $Script:LogFilePath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }

    Write-Log -Level Info -Message "Lade Konfiguration: $ConfigPath"
    Ensure-TargetDirectories -Targets $config.targets

    $statePath = Resolve-PathOrAbsolute -PathValue $config.stateFile
    $state = Load-State -StatePath $statePath

    $categoryRoutes = if ($config.categoryRoutes) { $config.categoryRoutes } else { @() }

    $aufgabenRoot = $null
    if ($config.aufgabenRoot) {
        $aufgabenRoot = Resolve-PathOrAbsolute -PathValue $config.aufgabenRoot
    }

    $registryFilePath = $null
    $praefixSuffixRegistry = [ordered]@{
        Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Suffixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    if ($config.projectRoutesFile) {
        $registryFilePath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesFile
        $praefixSuffixRegistry = Get-PraefixSuffixRegistry -Path $registryFilePath
    }

    $excludePaths = @()
    foreach ($target in $config.targets) {
        $excludePaths += $target.path
    }
    if ($aufgabenRoot) {
        $excludePaths += $aufgabenRoot
    }

    Copy-NewFiles -Sources $config.sources -Targets $config.targets -State $state -Rules $config.namingConventions -DefaultNameFormat $config.defaultNameFormat -CategoryRoutes $categoryRoutes -AufgabenRoot $aufgabenRoot -PraefixSuffixRegistry $praefixSuffixRegistry -RegistryFilePath $registryFilePath -ExcludePaths $excludePaths

    if (-not $DryRun) {
        Save-State -StatePath $statePath -State $state
    }

    Write-Log -Level Info -Message "Verarbeitung abgeschlossen."
}

Export-ModuleMember -Function Invoke-DocFlowEngine, Get-TargetFileName, Load-Config, Load-State, Save-State, Get-SourceFiles, Ensure-TargetDirectories, Resolve-PathOrAbsolute, Resolve-SourcePaths, Test-PathExcluded, Expand-Template, Write-Log, Copy-NewFiles, Get-FileCategory, Resolve-CategoryTarget, Get-FileProject, Get-ProjectRoutes, Resolve-ProjectTarget, Get-FilePraefixSuffix, Get-PraefixSuffixRegistry, Register-PraefixSuffix
