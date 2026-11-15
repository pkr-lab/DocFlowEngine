function Get-SourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] [string]$ResolvedPath
    )

    if (-not (Test-Path -LiteralPath $ResolvedPath)) {
        Write-Log -Level Warning -Message "Quellverzeichnis '$ResolvedPath' existiert nicht. Überspringe."
        return @()
    }

    $files = [ordered]@{}
    foreach ($pattern in $Source.includePatterns) {
        if ($Source.recursive) {
            $items = Get-ChildItem -LiteralPath $ResolvedPath -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue
        } else {
            $items = Get-ChildItem -LiteralPath $ResolvedPath -Filter $pattern -File -ErrorAction SilentlyContinue
        }

        foreach ($item in $items) {
            $files[$item.FullName] = $item
        }
    }

    foreach ($excludePattern in $Source.excludePatterns) {
        foreach ($key in @($files.Keys)) {
            if ($files[$key].Name -like $excludePattern) {
                $files.Remove($key)
            }
        }
    }

    return $files.Values
}

function Initialize-DocFlowTargetDirectories {
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

function Test-DocFlowInsideNamedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DirectoryName,
        [string]$FolderName
    )

    if (-not $FolderName) {
        return $false
    }

    $segments = $DirectoryName.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return ($segments -contains $FolderName)
}

function Get-DocFlowFileFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File
    )

    return [PSCustomObject]@{
        Length = [long]$File.Length
        LastWriteUtcSeconds = [long][Math]::Floor($File.LastWriteTimeUtc.Ticks / [TimeSpan]::TicksPerSecond)
    }
}

function Test-DocFlowSameFileVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [int]$ToleranceSeconds = 2
    )

    $fingerprint = Get-DocFlowFileFingerprint -File $File
    if ([long]$Entry['length'] -ne $fingerprint.Length) {
        return $false
    }

    return ([Math]::Abs([long]$Entry['lastWriteUtcSeconds'] - $fingerprint.LastWriteUtcSeconds) -le $ToleranceSeconds)
}

function Test-DocFlowHintFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string[]]$HintSuffixes = @()
    )

    foreach ($suffix in $HintSuffixes) {
        if ($suffix -and $Name.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Complete-DocFlowProcessedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [string]$SourceKey,
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [AllowEmptyCollection()] [array]$TargetPaths = @(),
        [AllowEmptyCollection()] [array]$HintSuffixes = @()
    )

    $fingerprint = Get-DocFlowFileFingerprint -File $File
    $State.processed[$SourceKey] = [ordered]@{
        source = $File.FullName
        targets = $TargetPaths
        processedAt = (Get-Date).ToString('o')
        length = $fingerprint.Length
        lastWriteUtcSeconds = $fingerprint.LastWriteUtcSeconds
    }

    foreach ($suffix in $HintSuffixes) {
        Remove-DocFlowHintFile -Path "$($File.FullName)$suffix" -Reason 'Datei wurde verarbeitet'
    }
}

function Get-DocFlowWhitelistRejectionReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject]$PraefixSuffix,
        $Registry
    )

    if ($Registry -and $Registry.Contains('Paare') -and $Registry.Paare) {
        if (-not $Registry.Paare.ContainsKey($PraefixSuffix.Praefix)) {
            return "Präfix '$($PraefixSuffix.Praefix)' ist nicht"
        }

        return "Suffix '$($PraefixSuffix.Suffix)' ist für Präfix '$($PraefixSuffix.Praefix)' nicht"
    }

    $unknownParts = @()
    if (-not ($Registry -and $Registry.Praefixe -and $Registry.Praefixe.Contains($PraefixSuffix.Praefix))) {
        $unknownParts += "Präfix '$($PraefixSuffix.Praefix)'"
    }
    if (-not ($Registry -and $Registry.Suffixe -and $Registry.Suffixe.Contains($PraefixSuffix.Suffix))) {
        $unknownParts += "Suffix '$($PraefixSuffix.Suffix)'"
    }

    return "$($unknownParts -join ' und ') nicht"
}

function Write-DocFlowResubmissionHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Rules,
        [hashtable]$DuplicateHint,
        [string]$TargetDirectory,
        [string]$ReviewMarkerPattern = $Script:DefaultReviewMarkerPattern
    )

    if (-not ($DuplicateHint -and $DuplicateHint.enabled)) {
        return
    }

    $suggestedName = Get-DocFlowSuggestedVersionName -File $File -Rules $Rules -TargetDirectory $TargetDirectory -ReviewMarkerPattern $ReviewMarkerPattern
    Write-DocFlowDuplicateHint -File $File -HintConfig $DuplicateHint -SuggestedName $suggestedName
}

function Test-DocFlowKnownFileUnchanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [System.IO.FileInfo]$File
    )

    if ($null -eq $Entry['length'] -or $null -eq $Entry['lastWriteUtcSeconds']) {
        $fingerprint = Get-DocFlowFileFingerprint -File $File
        $Entry['length'] = $fingerprint.Length
        $Entry['lastWriteUtcSeconds'] = $fingerprint.LastWriteUtcSeconds
        return $true
    }

    return (Test-DocFlowSameFileVersion -Entry $Entry -File $File)
}

function Resolve-DocFlowAufgabenRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [PSCustomObject]$PraefixSuffix,
        [Parameter(Mandatory)] [string]$AufgabenRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Rules,
        [hashtable]$PraefixSuffixRegistry,
        [string]$RegistryFilePath,
        [hashtable]$NamingConventionHint,
        [hashtable]$KuerzelRoutes,
        [string]$KuerzelRoutesFilePath
    )

    $route = [PSCustomObject]@{ TargetPath = $null; Rejected = $false }

    $isKnown = $false
    if ($PraefixSuffix) {
        $isKnown = (-not $RegistryFilePath) -or (Test-DocFlowPraefixSuffixKnown -Registry $PraefixSuffixRegistry -Praefix $PraefixSuffix.Praefix -Suffix $PraefixSuffix.Suffix)
    }

    if ($isKnown) {
        if ($KuerzelRoutes) {
            $initials = Get-FileInitials -File $File -Rules $Rules
            if ($initials) {
                Register-Kuerzel -Routes $KuerzelRoutes -RoutesFilePath $KuerzelRoutesFilePath -Kuerzel $initials -SourcePath $File.DirectoryName
            }
        }

        $route.TargetPath = Join-Path (Join-Path $AufgabenRoot $PraefixSuffix.Praefix) $PraefixSuffix.Suffix
        return $route
    }

    if (-not ($NamingConventionHint -and $NamingConventionHint.enabled)) {
        return $route
    }

    if ($PraefixSuffix) {
        $reason = Get-DocFlowWhitelistRejectionReason -PraefixSuffix $PraefixSuffix -Registry $PraefixSuffixRegistry
        Write-Log -Level Warning -Message "Datei '$($File.Name)': $reason in der Whitelist '$RegistryFilePath' eingetragen."
    } else {
        Write-Log -Level Warning -Message "Datei '$($File.Name)' passt nicht zum Schema initialen[_v<version>]_praefix_suffix_aufgabennummer (nur Buchstaben/Ziffern, keine Leerzeichen, Bindestriche oder Umlaute)."
    }
    Write-NamingConventionHint -File $File -HintConfig $NamingConventionHint -PraefixSuffix $PraefixSuffix
    $route.Rejected = $true
    return $route
}

function Copy-DocFlowFileToTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [array]$Targets,
        [Parameter(Mandatory)] [string]$TargetFileName,
        [Parameter(Mandatory)] [string]$SourceRoot,
        [int]$RetryCount = 2,
        [int]$RetryDelaySeconds = 5
    )

    $result = [PSCustomObject]@{ Succeeded = $true; TargetPaths = @() }

    foreach ($target in $Targets) {
        $destinationDirectory = $target.path
        if ($target.preserveSubfolders) {
            $relative = Get-DocFlowRelativePath -BasePath $SourceRoot -FullPath $File.DirectoryName
            if ($relative -and $relative -ne '.') {
                $destinationDirectory = Join-Path $destinationDirectory $relative
            }
        }

        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            if ($Script:DryRun) {
                Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $destinationDirectory"
            } else {
                Write-Log -Level Info -Message "Erstelle Verzeichnis: $destinationDirectory"
                try {
                    New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
                } catch {
                    Write-Log -Level Error -Message "Verzeichnis konnte nicht erstellt werden: '$destinationDirectory' ($($_.Exception.Message)). '$($File.Name)' wird beim nächsten Lauf erneut versucht."
                    $result.Succeeded = $false
                    continue
                }
            }
        }

        $destinationPath = Join-Path $destinationDirectory $TargetFileName

        if (Test-Path -LiteralPath $destinationPath) {
            Write-Log -Level Warning -Message "Zieldatei existiert bereits, überspringe Kopie: '$destinationPath'"
        } elseif ($Script:DryRun) {
            Write-Log -Level Info -Message "[DryRun] Datei würde kopiert: '$($File.FullName)' -> '$destinationPath'"
        } else {
            Write-Log -Level Info -Message "Kopiere Datei: '$($File.FullName)' -> '$destinationPath'"
            if (-not (Copy-DocFlowFileWithRetry -Source $File.FullName -Destination $destinationPath -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds)) {
                $result.Succeeded = $false
                continue
            }
        }

        $result.TargetPaths += $destinationPath
    }

    return $result
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
        [string]$AufgabenRoot = $null,
        [hashtable]$PraefixSuffixRegistry = $null,
        [string]$RegistryFilePath = $null,
        [array]$ExcludePaths = @(),
        [hashtable]$NamingConventionHint = $null,
        [hashtable]$DuplicateHint = $null,
        [hashtable]$KuerzelRoutes = $null,
        [string]$KuerzelRoutesFilePath = $null,
        [string]$KorrigiertFolderName = $null,
        [string]$ReviewMarkerPattern = $Script:DefaultReviewMarkerPattern,
        [double]$MinFileAgeMinutes = 0,
        [int]$RetryCount = 2,
        [int]$RetryDelaySeconds = 5
    )

    $hintSuffixes = @()
    if ($NamingConventionHint -and $NamingConventionHint.fileNameSuffix) {
        $hintSuffixes += $NamingConventionHint.fileNameSuffix
    }
    if ($DuplicateHint -and $DuplicateHint.fileNameSuffix) {
        $hintSuffixes += $DuplicateHint.fileNameSuffix
    }

    foreach ($source in $Sources) {
        $resolvedSourcePaths = Resolve-SourcePaths -PathValue $source.path
        if ($resolvedSourcePaths.Count -eq 0) {
            Write-Log -Level Warning -Message "Quellverzeichnis '$($source.path)' existiert nicht oder wurde nicht gefunden. Überspringe."
            continue
        }

        foreach ($resolvedSourcePath in $resolvedSourcePaths) {
            if ($hintSuffixes.Count -gt 0) {
                Remove-DocFlowOrphanedHintFiles -Directory $resolvedSourcePath -HintSuffixes $hintSuffixes -Recurse ([bool]$source.recursive)
            }

            $items = Get-SourceFiles -Source $source -ResolvedPath $resolvedSourcePath
            Write-Log -Level Info -Message "Gefundene Dateien in '$resolvedSourcePath': $($items.Count)"
            $alreadyProcessedCount = 0

            foreach ($item in $items) {
                if (Test-PathExcluded -FullName $item.FullName -ExcludePaths $ExcludePaths) {
                    continue
                }

                if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $KorrigiertFolderName) {
                    continue
                }

                if (Test-DocFlowHintFileName -Name $item.Name -HintSuffixes $hintSuffixes) {
                    continue
                }

                $relativeSourcePath = Get-DocFlowRelativePath -BasePath $resolvedSourcePath -FullPath $item.FullName
                $sourceKey = ("$($source.path)|$relativeSourcePath").ToLowerInvariant()
                $praefixSuffix = $null
                if ($AufgabenRoot) {
                    $praefixSuffix = Get-FilePraefixSuffix -File $item -Rules $Rules
                }

                if ($State.processed.ContainsKey($sourceKey)) {
                    if (Test-DocFlowKnownFileUnchanged -Entry $State.processed[$sourceKey] -File $item) {
                        $alreadyProcessedCount++
                        continue
                    }

                    if (-not (Test-DocFlowFileReady -File $item -MinAgeMinutes $MinFileAgeMinutes)) {
                        continue
                    }

                    Write-Log -Level Warning -Message "Datei '$($item.Name)' wurde nach der Abgabe unter gleichem Namen überschrieben. Sie wird nicht erneut kopiert; der Schüler soll eine Versionsangabe (_v2_ usw.) verwenden."
                    $suggestionDirectory = if ($praefixSuffix) { Join-Path (Join-Path $AufgabenRoot $praefixSuffix.Praefix) $praefixSuffix.Suffix } else { $null }
                    Write-DocFlowResubmissionHint -File $item -Rules $Rules -DuplicateHint $DuplicateHint -TargetDirectory $suggestionDirectory -ReviewMarkerPattern $ReviewMarkerPattern
                    continue
                }

                if (-not (Test-DocFlowFileReady -File $item -MinAgeMinutes $MinFileAgeMinutes)) {
                    continue
                }

                $targetFileName = Get-TargetFileName -File $item -Rules $Rules -DefaultFormat $DefaultNameFormat

                $effectiveTargets = $Targets
                $routingActive = $CategoryRoutes.Count -gt 0
                $routedTargetPath = $null
                $routedToAufgaben = $false

                if ($AufgabenRoot) {
                    $route = Resolve-DocFlowAufgabenRoute -File $item -PraefixSuffix $praefixSuffix -AufgabenRoot $AufgabenRoot -Rules $Rules -PraefixSuffixRegistry $PraefixSuffixRegistry -RegistryFilePath $RegistryFilePath -NamingConventionHint $NamingConventionHint -KuerzelRoutes $KuerzelRoutes -KuerzelRoutesFilePath $KuerzelRoutesFilePath
                    if ($route.Rejected) {
                        continue
                    }
                    $routedTargetPath = $route.TargetPath
                    $routedToAufgaben = [bool]$route.TargetPath
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
                    Write-Log -Level Warning -Message "Keine passende Kategorie-Zuordnung für '$($item.Name)' gefunden. Datei wird übersprungen."
                    continue
                } elseif (@($effectiveTargets).Count -eq 0) {
                    Write-Log -Level Warning -Message "Kein Ziel für '$($item.Name)' ermittelbar (kein gültiges Präfix/Suffix-Routing, keine 'targets' konfiguriert). Datei wird übersprungen."
                    continue
                }

                if ($routedToAufgaben) {
                    $existingSubmission = Find-DocFlowExistingSubmission -File $item -TargetDirectory $effectiveTargets[0].path
                    if ($existingSubmission) {
                        if ($existingSubmission.Length -eq $item.Length) {
                            Write-Log -Level Info -Message "Datei '$($item.Name)' liegt bereits identisch in '$($existingSubmission.FullName)'. Wird als verarbeitet übernommen."
                            Complete-DocFlowProcessedFile -State $State -SourceKey $sourceKey -File $item -TargetPaths @($existingSubmission.FullName) -HintSuffixes $hintSuffixes
                            continue
                        }

                        Write-Log -Level Warning -Message "Datei '$($item.Name)' wurde bereits abgegeben ('$($existingSubmission.Name)'). Sie wird nicht erneut kopiert; der Schüler soll eine Versionsangabe (_v2_ usw.) verwenden."
                        Write-DocFlowResubmissionHint -File $item -Rules $Rules -DuplicateHint $DuplicateHint -TargetDirectory $effectiveTargets[0].path -ReviewMarkerPattern $ReviewMarkerPattern
                        continue
                    }
                }

                $copyResult = Copy-DocFlowFileToTargets -File $item -Targets $effectiveTargets -TargetFileName $targetFileName -SourceRoot $resolvedSourcePath -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds
                if (-not $copyResult.Succeeded) {
                    continue
                }

                Complete-DocFlowProcessedFile -State $State -SourceKey $sourceKey -File $item -TargetPaths $copyResult.TargetPaths -HintSuffixes $hintSuffixes
            }

            if ($alreadyProcessedCount -gt 0) {
                Write-Log -Level Info -Message "Bereits in früheren Läufen verarbeitet und daher übersprungen: $alreadyProcessedCount"
            }
        }
    }
}
