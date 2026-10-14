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
        $regex = [regex]::new($rule.match, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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
        $regex = [regex]::new($rule.match, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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

    Write-DocFlowHintFile -Path $hintPath -Content $message -LogMessage "Datei '$($File.Name)' entspricht nicht der erwarteten Namenskonvention."
}

function Get-DocFlowSubmissionParts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [array]$Rules
    )

    foreach ($rule in $Rules) {
        $regex = [regex]::new($rule.match, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $regexMatch = $regex.Match($Name)
        if ($regexMatch.Success -and $regexMatch.Groups['initials'].Success -and $regexMatch.Groups['praefix'].Success -and $regexMatch.Groups['suffix'].Success -and $regexMatch.Groups['aufgabennummer'].Success) {
            $version = 1
            $versionTag = $regexMatch.Groups['versiontag']
            if ($versionTag.Success -and $versionTag.Value -match '(\d+)') {
                $version = [int]$Matches[1]
            }

            return [PSCustomObject]@{
                Initials = $regexMatch.Groups['initials'].Value
                Version = $version
                Praefix = $regexMatch.Groups['praefix'].Value
                Suffix = $regexMatch.Groups['suffix'].Value
                Aufgabennummer = $regexMatch.Groups['aufgabennummer'].Value
            }
        }
    }

    return $null
}

function Find-DocFlowExistingSubmission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$TargetDirectory
    )

    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        return $null
    }

    $pattern = '^\d{8}(?:\d{6})?_' + [regex]::Escape($File.Name) + '$'
    return Get-ChildItem -LiteralPath $TargetDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Select-Object -First 1
}

function Get-DocFlowSuggestedVersionName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Rules,
        [string]$TargetDirectory
    )

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $parts = Get-DocFlowSubmissionParts -Name $originalName -Rules $Rules
    if (-not $parts) {
        return $null
    }

    $candidates = @(Get-ChildItem -LiteralPath $File.DirectoryName -File -ErrorAction SilentlyContinue | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    if ($TargetDirectory -and (Test-Path -LiteralPath $TargetDirectory)) {
        $candidates += @(Get-ChildItem -LiteralPath $TargetDirectory -File -ErrorAction SilentlyContinue | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '^\d{8}(?:\d{6})?_', '' })
    }

    $highestVersion = $parts.Version
    foreach ($candidate in $candidates) {
        $candidateParts = Get-DocFlowSubmissionParts -Name ($candidate -replace '_k-[A-Za-z0-9]+$', '') -Rules $Rules
        if ($candidateParts -and
            $candidateParts.Initials -eq $parts.Initials -and
            $candidateParts.Praefix -eq $parts.Praefix -and
            $candidateParts.Suffix -eq $parts.Suffix -and
            $candidateParts.Aufgabennummer -eq $parts.Aufgabennummer -and
            $candidateParts.Version -gt $highestVersion) {
            $highestVersion = $candidateParts.Version
        }
    }

    $nextVersion = $highestVersion + 1
    return "$($parts.Initials)_v$($nextVersion)_$($parts.Praefix)_$($parts.Suffix)_$($parts.Aufgabennummer)$($File.Extension)"
}

function Write-DocFlowDuplicateHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [hashtable]$HintConfig,
        [string]$SuggestedName = ''
    )

    if (-not $HintConfig.enabled) {
        return
    }

    $hintPath = Join-Path $File.DirectoryName "$($File.Name)$($HintConfig.fileNameSuffix)"
    $context = [ordered]@{
        fileName = $File.Name
        suggestedName = $SuggestedName
    }
    $message = Expand-Template -Template $HintConfig.message -Context $context

    Write-DocFlowHintFile -Path $hintPath -Content $message -LogMessage "Datei '$($File.Name)' wurde bereits abgegeben."
}

function Get-DocFlowRegistryLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $result = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $Path)) {
        return ,$result
    }

    foreach ($line in @(Get-Content -Path $Path)) {
        if ($null -eq $line) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('#')) {
            $result.Add($trimmed)
            continue
        }

        foreach ($part in ($trimmed -split '(?i)(?<=\S)(?=(?:praefix|suffix)\s*=)')) {
            $result.Add($part.Trim())
        }
    }

    return ,$result
}

function ConvertTo-DocFlowRegistryStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Lines,
        [string]$SourceName = ''
    )

    $structure = [ordered]@{
        Groups = [ordered]@{}
        Orphans = New-Object System.Collections.Generic.List[string]
        Invalid = New-Object System.Collections.Generic.List[string]
    }
    $currentPraefix = $null

    foreach ($line in $Lines) {
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            $structure.Invalid.Add($line)
            continue
        }

        $key = $line.Substring(0, $separatorIndex).Trim().ToLowerInvariant()
        $value = $line.Substring($separatorIndex + 1).Trim()
        if (-not $value) {
            continue
        }

        if ($key -eq 'praefix') {
            $existingKey = @($structure.Groups.Keys | Where-Object { $_ -eq $value }) | Select-Object -First 1
            if ($existingKey) {
                $currentPraefix = $existingKey
            } else {
                $structure.Groups[$value] = New-Object System.Collections.Generic.List[string]
                $currentPraefix = $value
            }
        } elseif ($key -eq 'suffix') {
            if (-not $currentPraefix) {
                $structure.Orphans.Add($value)
                continue
            }

            $suffixes = $structure.Groups[$currentPraefix]
            if (-not ($suffixes | Where-Object { $_ -eq $value })) {
                $suffixes.Add($value)
            }
        } else {
            $structure.Invalid.Add($line)
        }
    }

    return $structure
}

function ConvertFrom-DocFlowRegistryStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Structure
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($praefix in $Structure.Groups.Keys) {
        $lines.Add("praefix=$praefix")
        foreach ($suffix in $Structure.Groups[$praefix]) {
            $lines.Add("suffix=$suffix")
        }
    }

    return ,$lines
}

function Get-PraefixSuffixRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $registry = [ordered]@{
        Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Suffixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Paare = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    if (-not (Test-Path $Path)) {
        Write-Log -Level Warning -Message "Registry-Datei '$Path' wurde nicht gefunden."
        return $registry
    }

    $structure = ConvertTo-DocFlowRegistryStructure -Lines (Get-DocFlowRegistryLines -Path $Path)

    foreach ($line in $structure.Invalid) {
        Write-Log -Level Warning -Message "Ungültige Zeile in Whitelist '$Path' ignoriert (erlaubt: praefix=<Name>, suffix=<Name>): '$line'"
    }
    foreach ($orphan in $structure.Orphans) {
        Write-Log -Level Warning -Message "Suffix '$orphan' in Whitelist '$Path' steht vor dem ersten praefix= und wird ignoriert."
    }

    $pairCount = 0
    foreach ($praefix in $structure.Groups.Keys) {
        [void]$registry.Praefixe.Add($praefix)
        $suffixSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($suffix in $structure.Groups[$praefix]) {
            [void]$suffixSet.Add($suffix)
            [void]$registry.Suffixe.Add($suffix)
            $pairCount++
        }
        $registry.Paare[$praefix] = $suffixSet
    }

    Write-Log -Level Info -Message "Whitelist geladen: '$Path' ($($registry.Praefixe.Count) Präfixe, $pairCount Kombinationen)"
    $pairDescriptions = foreach ($praefix in $registry.Paare.Keys) { "$praefix[$(@($registry.Paare[$praefix]) -join ', ')]" }
    Write-Log -Level Debug -Message "Whitelist-Kombinationen: $(@($pairDescriptions) -join ' | ')"

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

    $currentLines = @(Get-Content -Path $TargetPath | Where-Object { $null -ne $_ } | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $targetStructure = ConvertTo-DocFlowRegistryStructure -Lines (Get-DocFlowRegistryLines -Path $TargetPath)
    $seedStructure = ConvertTo-DocFlowRegistryStructure -Lines (Get-DocFlowRegistryLines -Path $SeedPath)

    foreach ($orphan in $targetStructure.Orphans) {
        Write-Log -Level Warning -Message "Suffix '$orphan' in Whitelist '$TargetPath' steht vor dem ersten praefix= und wird beim Abgleich entfernt."
    }

    $addedPairs = @()
    foreach ($praefix in $seedStructure.Groups.Keys) {
        $existingKey = @($targetStructure.Groups.Keys | Where-Object { $_ -eq $praefix }) | Select-Object -First 1
        if (-not $existingKey) {
            $targetStructure.Groups[$praefix] = New-Object System.Collections.Generic.List[string]
            $existingKey = $praefix
            $addedPairs += "praefix=$praefix"
        }

        $suffixes = $targetStructure.Groups[$existingKey]
        foreach ($suffix in $seedStructure.Groups[$praefix]) {
            if (-not ($suffixes | Where-Object { $_ -eq $suffix })) {
                $suffixes.Add($suffix)
                $addedPairs += "$existingKey/$suffix"
            }
        }
    }

    $newLines = ConvertFrom-DocFlowRegistryStructure -Structure $targetStructure
    $unchanged = ($newLines.Count -eq $currentLines.Count)
    if ($unchanged) {
        for ($index = 0; $index -lt $newLines.Count; $index++) {
            if ($newLines[$index] -cne $currentLines[$index]) {
                $unchanged = $false
                break
            }
        }
    }

    if ($unchanged) {
        return
    }

    $changeDescription = if ($addedPairs.Count -gt 0) { "ergänzt um: $($addedPairs -join ', ')" } else { 'nach Präfix gruppiert und bereinigt' }

    if ($Script:DryRun) {
        Write-Log -Level Info -Message "[DryRun] Whitelist-Datei '$TargetPath' würde neu geschrieben ($changeDescription)."
        return
    }

    Set-Content -Path $TargetPath -Value $newLines -Encoding UTF8
    Write-Log -Level Info -Message "Whitelist-Datei '$TargetPath' neu geschrieben ($changeDescription)."
}

function Test-DocFlowPraefixSuffixKnown {
    [CmdletBinding()]
    param(
        $Registry,
        [Parameter(Mandatory)] [string]$Praefix,
        [Parameter(Mandatory)] [string]$Suffix
    )

    if (-not $Registry) {
        return $false
    }

    if ($Registry.Contains('Paare') -and $Registry.Paare) {
        return $Registry.Paare.ContainsKey($Praefix) -and $Registry.Paare[$Praefix].Contains($Suffix)
    }

    if (-not $Registry.Praefixe -or -not $Registry.Suffixe) {
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

function ConvertTo-DocFlowAsciiName {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string]$Text
    )

    $replacements = @(
        @([char]0x00E4, 'ae'), @([char]0x00F6, 'oe'), @([char]0x00FC, 'ue'),
        @([char]0x00C4, 'Ae'), @([char]0x00D6, 'Oe'), @([char]0x00DC, 'Ue'),
        @([char]0x00DF, 'ss')
    )
    $result = $Text
    foreach ($replacement in $replacements) {
        $result = $result.Replace([string]$replacement[0], $replacement[1])
    }

    return $result
}

function Get-DocFlowNameProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [array]$Rules,
        $Registry = $null,
        [string]$KnownInitials = $null,
        [string]$Placeholder = 'PLATZHALTER'
    )

    $notes = New-Object System.Collections.Generic.List[string]

    $existingParts = Get-DocFlowSubmissionParts -Name $Name -Rules $Rules
    if ($existingParts) {
        return [PSCustomObject]@{ Stem = $Name; Compliant = $true; Initials = $existingParts.Initials; Version = $existingParts.Version; Praefix = $existingParts.Praefix; Suffix = $existingParts.Suffix; Aufgabennummer = $existingParts.Aufgabennummer; HasPlaceholder = $false; Notes = @() }
    }

    $cleaned = ConvertTo-DocFlowAsciiName -Text $Name
    $cleaned = $cleaned -replace '\s*\(\d+\)\s*$', ''
    $cleaned = $cleaned -replace '(?i)\s*-\s*(kopie|copy)(\s*\(\d+\))?\s*$', ''
    $cleaned = $cleaned -replace '(?i)^(kopie|copy)\s+(von|of)\s+', ''

    $tokens = @($cleaned -split '[^A-Za-z0-9]+' | Where-Object { $_ })
    $used = New-Object 'System.Collections.Generic.HashSet[int]'

    $version = 0
    for ($index = 0; $index -lt $tokens.Count; $index++) {
        if ($tokens[$index] -match '^(?i:v|version)(\d+)$') {
            $version = [int]$Matches[1]
            [void]$used.Add($index)
        }
    }

    $findToken = {
        param([string]$Value)
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            if (-not $used.Contains($i) -and $tokens[$i] -eq $Value) {
                return $i
            }
        }
        return -1
    }

    $praefix = $null
    $suffix = $null
    $hasPairs = $Registry -and $Registry.Contains('Paare') -and $Registry.Paare -and $Registry.Paare.Count -gt 0

    if ($hasPairs) {
        $pairs = foreach ($p in $Registry.Paare.Keys) { foreach ($s in $Registry.Paare[$p]) { [PSCustomObject]@{ Praefix = $p; Suffix = $s } } }
        $pairs = @($pairs)

        $strong = @($pairs | Where-Object { ((& $findToken $_.Praefix) -ge 0) -and ((& $findToken $_.Suffix) -ge 0) })
        if ($strong.Count -gt 1) {
            $longest = ($strong | ForEach-Object { $_.Suffix.Length } | Measure-Object -Maximum).Maximum
            $strong = @($strong | Where-Object { $_.Suffix.Length -eq $longest })
        }

        if ($strong.Count -eq 1) {
            $praefix = $strong[0].Praefix
            $suffix = $strong[0].Suffix
        } elseif ($strong.Count -gt 1) {
            $notes.Add('Präfix/Suffix mehrdeutig')
        } else {
            $compact = ($tokens -join '').ToLowerInvariant()
            $bySubstring = @($pairs | Where-Object { $compact.Contains($_.Praefix.ToLowerInvariant()) -and $compact.Contains($_.Suffix.ToLowerInvariant()) })
            if ($bySubstring.Count -gt 1) {
                $longest = ($bySubstring | ForEach-Object { $_.Praefix.Length + $_.Suffix.Length } | Measure-Object -Maximum).Maximum
                $bySubstring = @($bySubstring | Where-Object { ($_.Praefix.Length + $_.Suffix.Length) -eq $longest })
            }

            $bySuffix = @($pairs | Where-Object { (& $findToken $_.Suffix) -ge 0 })
            $byPraefix = @($Registry.Paare.Keys | Where-Object { (& $findToken $_) -ge 0 })

            if ($bySubstring.Count -eq 1) {
                $praefix = $bySubstring[0].Praefix
                $suffix = $bySubstring[0].Suffix
                $notes.Add('Präfix/Suffix aus zusammengeschriebenem Namen erkannt')
            } elseif ($bySuffix.Count -eq 1) {
                $praefix = $bySuffix[0].Praefix
                $suffix = $bySuffix[0].Suffix
                $notes.Add("Präfix aus Suffix '$suffix' abgeleitet")
            } elseif ($byPraefix.Count -eq 1) {
                $praefix = $byPraefix[0]
                $notes.Add('Suffix nicht erkannt')
            } elseif ($bySuffix.Count -gt 1 -and @($bySuffix | Select-Object -ExpandProperty Suffix -Unique).Count -eq 1) {
                $suffix = $bySuffix[0].Suffix
                $notes.Add("Suffix '$suffix' passt zu mehreren Präfixen ($(@($bySuffix | Select-Object -ExpandProperty Praefix) -join ', '))")
            } else {
                $notes.Add('Präfix/Suffix nicht erkannt')
            }
        }
    } elseif ($Registry) {
        if ($Registry.Praefixe) {
            $praefixMatches = @($Registry.Praefixe | Where-Object { (& $findToken $_) -ge 0 })
            if ($praefixMatches.Count -eq 1) {
                $praefix = $praefixMatches[0]
            }
        }
        if ($Registry.Suffixe) {
            $suffixMatches = @($Registry.Suffixe | Where-Object { ($_ -ne $praefix) -and ((& $findToken $_) -ge 0) })
            if ($suffixMatches.Count -eq 1) {
                $suffix = $suffixMatches[0]
            }
        }
    }

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($used.Contains($i)) {
            continue
        }
        $token = $tokens[$i]
        if (($praefix -and $token.IndexOf($praefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
            ($suffix -and $token.IndexOf($suffix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
            [void]$used.Add($i)
        }
    }

    $initials = $null
    if ($KnownInitials) {
        $initials = $KnownInitials
        $knownIndex = & $findToken $KnownInitials
        if ($knownIndex -ge 0) {
            [void]$used.Add($knownIndex)
        }
    } else {
        $remaining = @(0..([Math]::Max(0, $tokens.Count - 1)) | Where-Object { $tokens.Count -gt 0 -and -not $used.Contains($_) })
        if ($remaining.Count -gt 0 -and $tokens[$remaining[0]] -match '^[A-Za-z]{2,5}$') {
            $initials = $tokens[$remaining[0]]
            [void]$used.Add($remaining[0])
            $notes.Add('Initialen aus Dateinamen übernommen')
        }
    }

    $noiseWords = @('aufgabe', 'aufgaben', 'aufg', 'abgabe', 'loesung', 'final', 'fertig', 'neu', 'nr', 'kopie', 'copy')
    $aufgabennummer = $null
    for ($i = $tokens.Count - 1; $i -ge 0; $i--) {
        if (-not $used.Contains($i) -and ($noiseWords -notcontains $tokens[$i].ToLowerInvariant())) {
            $aufgabennummer = $tokens[$i]
            break
        }
    }

    if (-not $initials) { $initials = $Placeholder; $notes.Add('Initialen nicht erkannt') }
    if (-not $praefix) { $praefix = $Placeholder }
    if (-not $suffix) { $suffix = $Placeholder }
    if (-not $aufgabennummer) { $aufgabennummer = $Placeholder; $notes.Add('Aufgabennummer nicht erkannt') }

    $versionPart = if ($version -gt 0) { "_v$version" } else { '' }
    $stem = "${initials}${versionPart}_${praefix}_${suffix}_${aufgabennummer}"

    return [PSCustomObject]@{
        Stem = $stem
        Compliant = $false
        Initials = $initials
        Version = $version
        Praefix = $praefix
        Suffix = $suffix
        Aufgabennummer = $aufgabennummer
        HasPlaceholder = ($stem -match [regex]::Escape($Placeholder))
        Notes = @($notes)
    }
}

function Get-DocFlowMigratedFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [array]$Rules,
        $Registry = $null,
        [string]$Placeholder = 'PLATZHALTER'
    )

    return (Get-DocFlowNameProposal -Name $Name -Rules $Rules -Registry $Registry -Placeholder $Placeholder).Stem
}