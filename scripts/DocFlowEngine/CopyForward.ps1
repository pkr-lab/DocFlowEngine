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

    foreach ($excludePattern in $Source.excludePatterns) {
        foreach ($key in @($files.Keys)) {
            if ($files[$key].Name -like $excludePattern) {
                $files.Remove($key)
            }
        }
    }

    return $files.Values
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
        [array]$ExcludePaths = @(),
        [hashtable]$NamingConventionHint = $null,
        [hashtable]$DuplicateHint = $null,
        [hashtable]$KuerzelRoutes = $null,
        [string]$KuerzelRoutesFilePath = $null,
        [string]$KorrigiertFolderName = $null,
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
                    $entry = $State.processed[$sourceKey]
                    if ($null -eq $entry['length'] -or $null -eq $entry['lastWriteUtcSeconds']) {
                        $fingerprint = Get-DocFlowFileFingerprint -File $item
                        $entry['length'] = $fingerprint.Length
                        $entry['lastWriteUtcSeconds'] = $fingerprint.LastWriteUtcSeconds
                        $alreadyProcessedCount++
                        continue
                    }

                    if (Test-DocFlowSameFileVersion -Entry $entry -File $item) {
                        $alreadyProcessedCount++
                        continue
                    }

                    if (-not (Test-DocFlowFileReady -File $item -MinAgeMinutes $MinFileAgeMinutes)) {
                        continue
                    }

                    Write-Log -Level Warning -Message "Datei '$($item.Name)' wurde nach der Abgabe unter gleichem Namen überschrieben. Sie wird nicht erneut kopiert; der Schüler soll eine Versionsangabe (_v2_ usw.) verwenden."
                    if ($DuplicateHint -and $DuplicateHint.enabled) {
                        $suggestionDirectory = if ($praefixSuffix) { Join-Path (Join-Path $AufgabenRoot $praefixSuffix.Praefix) $praefixSuffix.Suffix } else { $null }
                        $suggestedName = Get-DocFlowSuggestedVersionName -File $item -Rules $Rules -TargetDirectory $suggestionDirectory
                        Write-DocFlowDuplicateHint -File $item -HintConfig $DuplicateHint -SuggestedName $suggestedName
                    }
                    continue
                }

                if (-not (Test-DocFlowFileReady -File $item -MinAgeMinutes $MinFileAgeMinutes)) {
                    continue
                }

                $targetFileName = Get-TargetFileName -File $item -Rules $Rules -DefaultFormat $DefaultNameFormat

                $effectiveTargets = $Targets
                $routingActive = ($ProjectRoutes.Count -gt 0) -or ($CategoryRoutes.Count -gt 0)
                $routedTargetPath = $null
                $routedToAufgaben = $false

                if ($AufgabenRoot) {
                    $praefixSuffixValid = $false
                    if ($praefixSuffix) {
                        if ($RegistryFilePath) {
                            $praefixSuffixValid = Test-DocFlowPraefixSuffixKnown -Registry $PraefixSuffixRegistry -Praefix $praefixSuffix.Praefix -Suffix $praefixSuffix.Suffix
                        } else {
                            $praefixSuffixValid = $true
                        }
                    }

                    if ($praefixSuffixValid) {
                        if ($KuerzelRoutes) {
                            $initials = Get-FileInitials -File $item -Rules $Rules
                            if ($initials) {
                                Register-Kuerzel -Routes $KuerzelRoutes -RoutesFilePath $KuerzelRoutesFilePath -Kuerzel $initials -SourcePath $item.DirectoryName
                            }
                        }

                        $routedTargetPath = Join-Path (Join-Path $AufgabenRoot $praefixSuffix.Praefix) $praefixSuffix.Suffix
                        $routedToAufgaben = $true
                    } elseif ($NamingConventionHint -and $NamingConventionHint.enabled) {
                        if ($praefixSuffix) {
                            $reason = Get-DocFlowWhitelistRejectionReason -PraefixSuffix $praefixSuffix -Registry $PraefixSuffixRegistry
                            Write-Log -Level Warning -Message "Datei '$($item.Name)': $reason in der Whitelist '$RegistryFilePath' eingetragen."
                        } else {
                            Write-Log -Level Warning -Message "Datei '$($item.Name)' passt nicht zum Schema initialen[_v<version>]_praefix_suffix_aufgabennummer (nur Buchstaben/Ziffern, keine Leerzeichen, Bindestriche oder Umlaute)."
                        }
                        Write-NamingConventionHint -File $item -HintConfig $NamingConventionHint -PraefixSuffix $praefixSuffix
                        continue
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
                        if ($DuplicateHint -and $DuplicateHint.enabled) {
                            $suggestedName = Get-DocFlowSuggestedVersionName -File $item -Rules $Rules -TargetDirectory $effectiveTargets[0].path
                            Write-DocFlowDuplicateHint -File $item -HintConfig $DuplicateHint -SuggestedName $suggestedName
                        }
                        continue
                    }
                }

                $targetPaths = @()
                $allCopiesSucceeded = $true

                foreach ($target in $effectiveTargets) {
                    $destinationDirectory = $target.path
                    if ($target.preserveSubfolders) {
                        $relative = Get-DocFlowRelativePath -BasePath $resolvedSourcePath -FullPath $item.DirectoryName
                        if ($relative -and $relative -ne '.') {
                            $destinationDirectory = Join-Path $destinationDirectory $relative
                        }
                    }

                    if (-not (Test-Path $destinationDirectory)) {
                        if ($Script:DryRun) {
                            Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $destinationDirectory"
                        } else {
                            Write-Log -Level Info -Message "Erstelle Verzeichnis: $destinationDirectory"
                            try {
                                New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
                            } catch {
                                Write-Log -Level Error -Message "Verzeichnis konnte nicht erstellt werden: '$destinationDirectory' ($($_.Exception.Message)). '$($item.Name)' wird beim nächsten Lauf erneut versucht."
                                $allCopiesSucceeded = $false
                                continue
                            }
                        }
                    }

                    $destinationPath = Join-Path $destinationDirectory $targetFileName

                    if (Test-Path $destinationPath) {
                        Write-Log -Level Warning -Message "Zieldatei existiert bereits, überspringe Kopie: '$destinationPath'"
                    } elseif ($Script:DryRun) {
                        Write-Log -Level Info -Message "[DryRun] Datei würde kopiert: '$($item.FullName)' -> '$destinationPath'"
                    } else {
                        Write-Log -Level Info -Message "Kopiere Datei: '$($item.FullName)' -> '$destinationPath'"
                        if (-not (Copy-DocFlowFileWithRetry -Source $item.FullName -Destination $destinationPath -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds)) {
                            $allCopiesSucceeded = $false
                            continue
                        }
                    }

                    $targetPaths += $destinationPath
                }

                if (-not $allCopiesSucceeded) {
                    continue
                }

                Complete-DocFlowProcessedFile -State $State -SourceKey $sourceKey -File $item -TargetPaths $targetPaths -HintSuffixes $hintSuffixes
            }

            if ($alreadyProcessedCount -gt 0) {
                Write-Log -Level Info -Message "Bereits in früheren Läufen verarbeitet und daher übersprungen: $alreadyProcessedCount"
            }
        }
    }
}
