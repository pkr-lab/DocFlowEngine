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
        [hashtable]$KuerzelRoutes = $null,
        [string]$KuerzelRoutesFilePath = $null,
        [string]$KorrigiertFolderName = $null
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

                if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $KorrigiertFolderName) {
                    continue
                }

                $relativeSourcePath = Get-DocFlowRelativePath -BasePath $resolvedSourcePath -FullPath $item.FullName
                $sourceKey = ("$($source.path)|$relativeSourcePath").ToLowerInvariant()
                if ($State.processed.ContainsKey($sourceKey)) {
                    continue
                }

                $targetFileName = Get-TargetFileName -File $item -Rules $Rules -DefaultFormat $DefaultNameFormat

                $effectiveTargets = $Targets
                $routingActive = ($ProjectRoutes.Count -gt 0) -or ($CategoryRoutes.Count -gt 0)
                $routedTargetPath = $null

                if ($AufgabenRoot) {
                    $praefixSuffix = Get-FilePraefixSuffix -File $item -Rules $Rules

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
                    } elseif ($NamingConventionHint -and $NamingConventionHint.enabled) {
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
                }

                $targetPaths = @()

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
                            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                        }
                    }

                    $destinationPath = Join-Path $destinationDirectory $targetFileName

                    if (Test-Path $destinationPath) {
                        Write-Log -Level Warning -Message "Zieldatei existiert bereits, überspringe Kopie: '$destinationPath'"
                    } elseif ($Script:DryRun) {
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
