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
        # Direkt mit [regex]::Match statt dem -match-Operator/$Matches: Ein
        # .NET Group-Objekt liefert für eine nicht mitgematchte optionale Gruppe
        # (z. B. "versiontag" ohne Versionsangabe) garantiert .Value = '' -
        # unabhängig davon, ob $Matches für diese Gruppe überhaupt einen
        # Schlüssel anlegt. Damit bleibt kein Platzhalter wie "{versiontag}"
        # unersetzt im Dateinamen stehen.
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

function Get-FileInitials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

    foreach ($rule in $Rules) {
        # Wie bei Get-TargetFileName: [regex]::Match statt -match/$Matches, damit
        # eine vorhandene, aber nicht benannte "initials"-Gruppe zuverlässig erkannt wird.
        $regex = [regex]::new($rule.match)
        $regexMatch = $regex.Match($originalName)
        if ($regexMatch.Success -and $regexMatch.Groups['initials'].Success) {
            return $regexMatch.Groups['initials'].Value
        }
    }

    return $null
}

function Write-NamingConventionHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [hashtable]$HintConfig,
        # Optional: bereits erkanntes, aber unbekanntes Präfix/Suffix (siehe
        # Test-DocFlowPraefixSuffixKnown), damit die Hinweismeldung bei Bedarf
        # {praefix}/{suffix} referenzieren kann, statt nur allgemein auf das
        # Namensschema zu verweisen.
        [PSCustomObject]$PraefixSuffix = $null
    )

    if (-not $HintConfig.enabled) {
        return
    }

    # Pro-Datei-Hinweis statt einer geteilten Ordner-Hinweisdatei: so bleibt
    # erkennbar, welche konkrete Datei betroffen ist, und ein neuer Fehler in
    # einem Ordner mit bereits vorhandenem Hinweis wird nicht mehr verschluckt
    # (siehe ERWEITERUNGSKONZEPT.md, Abschnitt 2a).
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

function Test-DocFlowPraefixSuffixKnown {
    [CmdletBinding()]
    param(
        [hashtable]$Registry,
        [Parameter(Mandatory)] [string]$Praefix,
        [Parameter(Mandatory)] [string]$Suffix
    )

    # Präfix und Suffix gelten nur als bekannt, wenn beide bereits einzeln in der
    # (statisch gepflegten, siehe config/project-routes.txt) Registry stehen. Neue
    # Werte werden nicht mehr automatisch aufgenommen - eine unbekannte Kombination
    # ist ein Namenskonvention-Fehler (siehe Copy-NewFiles/Write-NamingConventionHint).
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
