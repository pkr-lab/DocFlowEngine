#Requires -Version 5.1

param(
    [string[]]$Path = @(),
    [string]$ConfigPath = '.\config\docflow-config.psd1',
    [switch]$Apply,
    [string]$ReportPath = $null,
    [string]$Undo = $null,
    [switch]$MarkAsProcessed,
    [switch]$IncludeUnrecognized,
    [string]$Placeholder = 'PLATZHALTER'
)

$modulePath = Join-Path $PSScriptRoot 'DocFlowEngine.psm1'
if (-not (Test-Path $modulePath)) {
    throw "Moduldatei '$modulePath' wurde nicht gefunden."
}

Import-Module -Name $modulePath -Force

function New-RenameResult {
    param(
        [Parameter(Mandatory)] [string]$Status,
        [Parameter(Mandatory)] [System.IO.FileInfo]$Item,
        [Parameter(Mandatory)] [string]$NewName,
        [Parameter(Mandatory)] [string]$NewPath,
        [string]$Notes = ''
    )

    return [PSCustomObject]@{ Status = $Status; Ordner = $Item.DirectoryName; Alt = $Item.Name; Neu = $NewName; Hinweise = $Notes; AlterPfad = $Item.FullName; NeuerPfad = $NewPath; Ausgefuehrt = 'nein' }
}

if ($Undo) {
    $undoResult = Undo-DocFlowRename -ReportPath $Undo
    Write-Host "$($undoResult.Restored) von $($undoResult.Total) Umbenennung(en) rückgängig gemacht."
    return
}

$config = Import-DocFlowConfig -Path $ConfigPath

$registry = $null
if ($config.projectRoutesFile) {
    $registryPath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesFile
    if (-not (Test-Path $registryPath) -and $config.projectRoutesSeedFile) {
        $registryPath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesSeedFile
    }
    $registry = Get-PraefixSuffixRegistry -Path $registryPath
}

$kuerzelByFolder = @{}
if ($config.reviewMarker.kuerzelRoutesFile) {
    $kuerzelRoutes = Get-KuerzelRoutes -Path (Resolve-PathOrAbsolute -PathValue $config.reviewMarker.kuerzelRoutesFile)
    $kuerzelByFolder = ConvertTo-DocFlowKuerzelByFolder -KuerzelRoutes $kuerzelRoutes
}

$lockPath = $null
$lockAcquired = $true
if ($config.lockFile -and $Apply) {
    $lockPath = Resolve-PathOrAbsolute -PathValue $config.lockFile
    $lockAcquired = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes $config.lockTimeoutMinutes
}

if (-not $lockAcquired) {
    Write-Warning "Abgebrochen: eine andere DocFlowEngine-Instanz ist aktiv (Lock-Datei '$lockPath')."
    return
}

try {
    $statePath = Resolve-PathOrAbsolute -PathValue $config.stateFile
    $state = Import-DocFlowState -StatePath $statePath

    $scanRoots = @()
    if ($Path.Count -gt 0) {
        foreach ($entry in $Path) {
            if (-not (Test-Path -LiteralPath $entry)) {
                throw "Pfad '$entry' wurde nicht gefunden."
            }
            $scanRoots += (Resolve-PathOrAbsolute -PathValue $entry)
        }
    } else {
        foreach ($source in $config.sources) {
            $scanRoots += @(Resolve-SourcePaths -PathValue $source.path)
        }
    }

    if ($scanRoots.Count -eq 0) {
        throw "Kein Ordner zum Durchsuchen gefunden. -Path angeben oder 'sources' in der Konfiguration prüfen."
    }

    $includePatterns = @($config.sources | ForEach-Object { $_.includePatterns } | Where-Object { $_ } | Select-Object -Unique)
    $excludePatterns = @($config.sources | ForEach-Object { $_.excludePatterns } | Where-Object { $_ } | Select-Object -Unique)
    $protectedRoots = @()
    if ($config.aufgabenRoot) {
        $protectedRoots += (Resolve-PathOrAbsolute -PathValue $config.aufgabenRoot)
    }
    foreach ($target in @($config.targets)) {
        if ($target.path) {
            $protectedRoots += (Resolve-PathOrAbsolute -PathValue $target.path)
        }
    }
    $korrigiertFolderName = $config.reviewMarker.korrigiertFolderName

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $scanRoots) {
        foreach ($item in (Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue)) {
            if (-not $seen.Add($item.FullName)) {
                continue
            }
            if (Test-PathExcluded -FullName $item.FullName -ExcludePaths $protectedRoots) {
                continue
            }
            if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $korrigiertFolderName) {
                continue
            }
            if ($includePatterns.Count -gt 0 -and -not ($includePatterns | Where-Object { $item.Name -like $_ })) {
                continue
            }
            if ($excludePatterns | Where-Object { $item.Name -like $_ }) {
                continue
            }
            $files.Add($item)
        }
    }

    $initialsByFolder = Get-DocFlowFolderInitials -Files $files -Rules $config.namingConventions -Registry $registry -KuerzelByFolder $kuerzelByFolder -Placeholder $Placeholder

    $plannedDestinations = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $files) {
        $originalStem = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
        $extension = [System.IO.Path]::GetExtension($item.Name)
        $folder = $item.DirectoryName.TrimEnd('\', '/')
        $knownInitials = if ($initialsByFolder.ContainsKey($folder)) { $initialsByFolder[$folder].Initials } else { $null }

        $proposal = Get-DocFlowNameProposal -Name $originalStem -Rules $config.namingConventions -Registry $registry -KnownInitials $knownInitials -Placeholder $Placeholder
        $notes = @($proposal.Notes)
        if ($knownInitials -and -not $proposal.Compliant) {
            $notes = @("Initialen '$knownInitials' $($initialsByFolder[$folder].Source)") + $notes
        }

        if ($proposal.Compliant) {
            if ($registry -and -not (Test-DocFlowPraefixSuffixKnown -Registry $registry -Praefix $proposal.Praefix -Suffix $proposal.Suffix)) {
                $notes += "Kombination $($proposal.Praefix)/$($proposal.Suffix) steht nicht in der Whitelist"
            }
            $results.Add((New-RenameResult -Status 'bereits regelkonform' -Item $item -NewName $item.Name -NewPath $item.FullName -Notes ($notes -join '; ')))
            [void]$plannedDestinations.Add($item.FullName)
            continue
        }

        if (-not $IncludeUnrecognized -and $proposal.Praefix -eq $Placeholder -and $proposal.Suffix -eq $Placeholder) {
            $results.Add((New-RenameResult -Status 'unverändert (kein Fach erkannt)' -Item $item -NewName $item.Name -NewPath $item.FullName -Notes "Vorschlag wäre '$($proposal.Stem)$extension'; mit -IncludeUnrecognized trotzdem umbenennen"))
            [void]$plannedDestinations.Add($item.FullName)
            continue
        }

        $version = $proposal.Version
        $stem = New-DocFlowSubmissionStem -Initials $proposal.Initials -Version $version -Praefix $proposal.Praefix -Suffix $proposal.Suffix -Aufgabennummer $proposal.Aufgabennummer
        $destinationPath = Join-Path $item.DirectoryName "$stem$extension"
        while (((Test-Path -LiteralPath $destinationPath) -and -not $destinationPath.Equals($item.FullName, [System.StringComparison]::OrdinalIgnoreCase)) -or $plannedDestinations.Contains($destinationPath)) {
            $version = [Math]::Max($version, 1) + 1
            $stem = New-DocFlowSubmissionStem -Initials $proposal.Initials -Version $version -Praefix $proposal.Praefix -Suffix $proposal.Suffix -Aufgabennummer $proposal.Aufgabennummer
            $destinationPath = Join-Path $item.DirectoryName "$stem$extension"
        }
        if ($version -ne $proposal.Version) {
            $notes += "Name war schon vergeben, Version _v$version gesetzt"
        }
        [void]$plannedDestinations.Add($destinationPath)

        $status = if ($proposal.HasPlaceholder) { 'umbenannt mit Platzhalter' } else { 'umbenannt' }
        $results.Add((New-RenameResult -Status $status -Item $item -NewName "$stem$extension" -NewPath $destinationPath -Notes ($notes -join '; ')))
    }

    if ($Apply) {
        foreach ($result in $results) {
            if ($result.Status -notlike 'umbenannt*') {
                continue
            }

            try {
                Rename-Item -LiteralPath $result.AlterPfad -NewName $result.Neu -ErrorAction Stop
                $result.Ausgefuehrt = 'ja'
            } catch {
                $result.Status = 'Fehler'
                $result.Hinweise = (@($result.Hinweise, $_.Exception.Message) | Where-Object { $_ }) -join '; '
                continue
            }

            if ($MarkAsProcessed) {
                foreach ($source in $config.sources) {
                    foreach ($resolvedSourcePath in (Resolve-SourcePaths -PathValue $source.path)) {
                        if ($result.NeuerPfad.StartsWith($resolvedSourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $relativePath = Get-DocFlowRelativePath -BasePath $resolvedSourcePath -FullPath $result.NeuerPfad
                            $sourceKey = ("$($source.path)|$relativePath").ToLowerInvariant()
                            $fingerprint = Get-DocFlowFileFingerprint -File (Get-Item -LiteralPath $result.NeuerPfad)
                            $state.processed[$sourceKey] = [ordered]@{
                                source = $result.NeuerPfad
                                targets = @()
                                processedAt = (Get-Date).ToString('o')
                                length = $fingerprint.Length
                                lastWriteUtcSeconds = $fingerprint.LastWriteUtcSeconds
                                migriert = $true
                            }
                        }
                    }
                }
            }
        }

        if ($MarkAsProcessed) {
            Save-State -StatePath $statePath -State $state
        }
    }

    if (-not $ReportPath) {
        $ReportPath = Join-Path (Get-Location) ("Umbenennung-{0}{1}.csv" -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $(if ($Apply) { '' } else { '-Vorschau' }))
    }
    $results | Select-Object Status, Ordner, Alt, Neu, Hinweise, AlterPfad, NeuerPfad, Ausgefuehrt | Export-Csv -LiteralPath $ReportPath -Delimiter ';' -Encoding UTF8 -NoTypeInformation

    $results | Where-Object { $_.Status -ne 'bereits regelkonform' } | Format-Table -AutoSize -Wrap -Property Status, Alt, Neu, Hinweise | Out-String -Width 300 | Write-Host

    $renamed = @($results | Where-Object { $_.Status -like 'umbenannt*' })
    $withPlaceholder = @($results | Where-Object { $_.Status -eq 'umbenannt mit Platzhalter' })
    $compliant = @($results | Where-Object { $_.Status -eq 'bereits regelkonform' })
    $failed = @($results | Where-Object { $_.Status -eq 'Fehler' })
    $skipped = @($results | Where-Object { $_.Status -like 'unverändert*' })

    if ($Apply) {
        Write-Host "$($renamed.Count) Datei(en) umbenannt, davon $($withPlaceholder.Count) mit Platzhalter. $($compliant.Count) bereits regelkonform, $($skipped.Count) ohne erkennbares Fach unverändert. $($failed.Count) Fehler."
        Write-Host "Protokoll (auch zum Rückgängigmachen mit -Undo): $ReportPath"
    } else {
        Write-Host "VORSCHAU - nichts wurde verändert: $($renamed.Count) Datei(en) würden umbenannt, davon $($withPlaceholder.Count) mit Platzhalter. $($compliant.Count) bereits regelkonform, $($skipped.Count) ohne erkennbares Fach unverändert."
        Write-Host "Vorschau-Tabelle: $ReportPath"
        Write-Host "Zum Umbenennen denselben Aufruf mit -Apply wiederholen."
    }
} finally {
    if ($lockPath -and $lockAcquired) {
        Unlock-DocFlowRun -LockPath $lockPath
    }
}