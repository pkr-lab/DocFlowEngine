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
        $regex = [regex]::new($rule.match)
        $regexMatch = $regex.Match($originalName)
        if ($regexMatch.Success) {
            foreach ($groupName in $regex.GetGroupNames()) {
                if ($groupName -eq '0') {
                    continue
                }

                $context[$groupName] = $regexMatch.Groups[$groupName].Value
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

function Get-FileInitialsFromName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [array]$Rules
    )

    foreach ($rule in $Rules) {
        $regex = [regex]::new($rule.match)
        $regexMatch = $regex.Match($Name)
        if ($regexMatch.Success -and $regexMatch.Groups['initials'].Success) {
            return $regexMatch.Groups['initials'].Value
        }
    }

    return $null
}

function Get-FileInitials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    return Get-FileInitialsFromName -Name $originalName -Rules $Rules
}

function Write-NamingConventionHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [hashtable]$HintConfig,
        [PSCustomObject]$PraefixSuffix = $null
    )

    if (-not $HintConfig.enabled) {
        return
    }

    $hintFileName = "$($File.Name)$($HintConfig.fileNameSuffix)"
    $hintPath = Join-Path $File.DirectoryName $hintFileName
    if (Test-Path $hintPath) {
        return
    }

    $context = [ordered]@{
        originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        extension = [System.IO.Path]::GetExtension($File.Name).TrimStart('.')
        fileName = $File.Name
        praefix = if ($PraefixSuffix) { $PraefixSuffix.Praefix } else { '' }
        suffix = if ($PraefixSuffix) { $PraefixSuffix.Suffix } else { '' }
    }
    $message = Expand-Template -Template $HintConfig.message -Context $context

    if ($Script:DryRun) {
        Write-Log -Level Warning -Message "[DryRun] Datei '$($File.Name)' entspricht nicht der erwarteten Namenskonvention. Hinweis-Datei würde erstellt: '$hintPath'"
    } else {
        Write-Log -Level Warning -Message "Datei '$($File.Name)' entspricht nicht der erwarteten Namenskonvention. Hinweis-Datei erstellt: '$hintPath'"
        Set-Content -Path $hintPath -Value $message -Encoding UTF8
    }
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

function Sync-ProjectRoutesFromSeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SeedPath,
        [Parameter(Mandatory)] [string]$TargetPath
    )

    if ($SeedPath.Equals($TargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    if (-not (Test-Path $SeedPath)) {
        Write-Log -Level Warning -Message "Whitelist-Startbestand '$SeedPath' wurde nicht gefunden. Synchronisierung übersprungen."
        return
    }

    if (-not (Test-Path $TargetPath)) {
        $targetDirectory = Split-Path -Path $TargetPath -Parent
        if ($targetDirectory -and -not (Test-Path $targetDirectory)) {
            if ($Script:DryRun) {
                Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $targetDirectory"
            } else {
                New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
            }
        }

        if ($Script:DryRun) {
            Write-Log -Level Info -Message "[DryRun] Whitelist-Datei würde aus Startbestand erstellt: '$TargetPath' (aus '$SeedPath')"
        } else {
            Copy-Item -Path $SeedPath -Destination $TargetPath -Force
            Write-Log -Level Info -Message "Whitelist-Datei aus Startbestand erstellt: '$TargetPath' (aus '$SeedPath')"
        }

        return
    }

    $existingLines = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-Content -Path $TargetPath), [System.StringComparer]::OrdinalIgnoreCase)
    $missingLines = @()

    foreach ($line in Get-Content -Path $SeedPath) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#') -or $existingLines.Contains($trimmed)) {
            continue
        }

        $missingLines += $trimmed
        [void]$existingLines.Add($trimmed)
    }

    if ($missingLines.Count -eq 0) {
        return
    }

    if ($Script:DryRun) {
        Write-Log -Level Info -Message "[DryRun] Whitelist-Datei '$TargetPath' würde um Eintraege aus Startbestand ergänzt: $($missingLines -join ', ')"
    } else {
        Add-Content -Path $TargetPath -Value $missingLines
        Write-Log -Level Info -Message "Whitelist-Datei '$TargetPath' um Eintraege aus Startbestand ergänzt: $($missingLines -join ', ')"
    }
}

function Test-DocFlowPraefixSuffixKnown {
    [CmdletBinding()]
    param(
        [hashtable]$Registry,
        [Parameter(Mandatory)] [string]$Praefix,
        [Parameter(Mandatory)] [string]$Suffix
    )

    if (-not $Registry -or -not $Registry.Praefixe -or -not $Registry.Suffixe) {
        return $false
    }

    return $Registry.Praefixe.Contains($Praefix) -and $Registry.Suffixe.Contains($Suffix)
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

function Get-DocFlowMigratedFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [array]$Rules,
        [hashtable]$Registry = $null,
        [string]$Placeholder = 'PLATZHALTER'
    )

    foreach ($rule in $Rules) {
        if ([regex]::new($rule.match).Match($Name).Success) {
            return $Name
        }
    }

    $tokens = @($Name -split '[_\-\s\.]+' | Where-Object { $_ })
    $usedTokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $praefix = $Placeholder
    if ($Registry -and $Registry.Praefixe) {
        $praefixMatches = @($Registry.Praefixe | Where-Object { $tokens -contains $_ })
        if ($praefixMatches.Count -eq 1) {
            $praefix = $praefixMatches[0]
            [void]$usedTokens.Add($praefix)
        }
    }

    $suffix = $Placeholder
    if ($Registry -and $Registry.Suffixe) {
        $suffixMatches = @($Registry.Suffixe | Where-Object { ($tokens -contains $_) -and (-not $usedTokens.Contains($_)) })
        if ($suffixMatches.Count -eq 1) {
            $suffix = $suffixMatches[0]
            [void]$usedTokens.Add($suffix)
        }
    }

    $remainingTokens = @($tokens | Where-Object { -not $usedTokens.Contains($_) })

    $initials = $Placeholder
    if ($remainingTokens.Count -gt 0 -and $remainingTokens[0] -match '^[A-Za-z]{2,5}$') {
        $initials = $remainingTokens[0]
        $remainingTokens = @($remainingTokens | Select-Object -Skip 1)
    }

    $aufgabennummer = $Placeholder
    if ($remainingTokens.Count -gt 0 -and $remainingTokens[-1] -match '^[A-Za-z0-9]+$') {
        $aufgabennummer = $remainingTokens[-1]
    }

    return "${initials}_${praefix}_${suffix}_${aufgabennummer}"
}
