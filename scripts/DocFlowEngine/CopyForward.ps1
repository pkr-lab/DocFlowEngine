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

                # Bereits zurückkopierte, korrigierte Dateien liegen im
                # Korrigiert-Unterordner desselben Quellordners (siehe
                # Copy-ReviewedFiles) und dürfen hier nicht erneut als "neue"
                # Quelldatei aufgegriffen werden - sonst entsteht eine Schleife.
                if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $KorrigiertFolderName) {
                    continue
                }

                # Dedup-Key relativ zur (ggf. wildcardhaltigen) Quellwurzel statt
                # zum vollen aufgelösten Pfad: Auf verschiedenen Rechnern liefert
                # derselbe Wildcard-Quellpfad unterschiedliche aufgelöste Pfade
                # (z. B. abweichender Windows-Benutzername), aber $source.path
                # aus der Konfiguration ist auf jedem Rechner identisch. Siehe
                # MULTI-MACHINE-SETUP.md, Baustein 1.
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

                    # Präfix/Suffix müssen dem Namensschema entsprechen UND (falls eine
                    # Registry konfiguriert ist) bereits als bekannt hinterlegt sein.
                    # Anders als früher wird ein neuer, unbekannter Präfix/Suffix NICHT
                    # mehr automatisch akzeptiert und in die Registry aufgenommen,
                    # sondern wie ein Namenskonvention-Fehler behandelt. Ohne
                    # konfigurierte Registry (kein RegistryFilePath) bleibt es beim alten,
                    # permissiven Verhalten.
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
                                # Bewusst der unmittelbare Ordner der Datei ($item.DirectoryName),
                                # nicht die (ggf. für alle Schüler gemeinsame) Quellwurzel
                                # $resolvedSourcePath: Nur so wird bei einem rekursiv gescannten,
                                # gemeinsamen Austauschordner mit Schüler-Unterordnern der
                                # tatsächliche, individuelle Schülerordner registriert.
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

                    # Defense-in-Depth für den Multi-Machine-Betrieb (siehe
                    # MULTI-MACHINE-SETUP.md, Baustein 5): existiert die Zieldatei
                    # bereits (z. B. weil die State-Datei zwischen Rechnern noch
                    # nicht synchronisiert ist), wird sie nicht mit -Force
                    # überschrieben, sondern übersprungen.
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
