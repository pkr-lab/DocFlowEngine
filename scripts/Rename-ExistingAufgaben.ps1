#Requires -Version 5.1

param(
    [Parameter(Mandatory)] [string]$Path,
    [string]$ConfigPath = '.\config\docflow-config.psd1',
    [switch]$Apply
)

$modulePath = Join-Path $PSScriptRoot 'DocFlowEngine.psm1'
if (-not (Test-Path $modulePath)) {
    throw "Moduldatei '$modulePath' wurde nicht gefunden."
}

Import-Module -Name $modulePath -Force

if (-not (Test-Path $Path)) {
    throw "Pfad '$Path' wurde nicht gefunden."
}

$config = Load-Config -Path $ConfigPath

$registry = $null
if ($config.projectRoutesFile) {
    $registryPath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesFile
    $registry = Get-PraefixSuffixRegistry -Path $registryPath
}

$lockPath = $null
$lockAcquired = $true
if ($config.lockFile) {
    $lockPath = Resolve-PathOrAbsolute -PathValue $config.lockFile
    $lockAcquired = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes $config.lockTimeoutMinutes
}

if (-not $lockAcquired) {
    Write-Warning "Abgebrochen: eine andere DocFlowEngine-Instanz ist aktiv (Lock-Datei '$lockPath')."
    return
}

try {
    $statePath = Resolve-PathOrAbsolute -PathValue $config.stateFile
    $state = Load-State -StatePath $statePath

    $resolvedTargetPath = Resolve-PathOrAbsolute -PathValue $Path
    $matchingSource = $null
    foreach ($source in $config.sources) {
        foreach ($resolvedSourcePath in (Resolve-SourcePaths -PathValue $source.path)) {
            if ($resolvedTargetPath.StartsWith($resolvedSourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchingSource = $source
            }
        }
    }

    if (-not $matchingSource) {
        Write-Warning "'$Path' liegt unter keinem konfigurierten 'sources[]'-Eintrag. Umbenennung laeuft trotzdem, aber die Dateien werden NICHT in der Zustandsdatei registriert - DocFlowEngine wuerde sie beim naechsten Lauf ggf. wie neue Dateien behandeln."
    }

    $namingConventionHintSuffix = $config.namingConventionHint.fileNameSuffix
    $korrigiertFolderName = $config.reviewMarker.korrigiertFolderName
    $plannedDestinations = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $results = @()

    $items = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue

    foreach ($item in $items) {
        if ($namingConventionHintSuffix -and $item.Name.EndsWith($namingConventionHintSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($item.Name.EndsWith('.KUERZEL-UNBEKANNT.txt', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $korrigiertFolderName) {
            continue
        }

        $originalName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
        $extension = [System.IO.Path]::GetExtension($item.Name)

        $newStem = Get-DocFlowMigratedFileName -Name $originalName -Rules $config.namingConventions -Registry $registry

        if ($newStem -eq $originalName) {
            $results += [PSCustomObject]@{ Original = $item.Name; Neu = $item.Name; Status = 'bereits regelkonform' }
            continue
        }

        $newName = "$newStem$extension"
        $destinationPath = Join-Path $item.DirectoryName $newName
        $suffixCounter = 2
        while ((Test-Path $destinationPath) -or $plannedDestinations.Contains($destinationPath.ToLowerInvariant())) {
            $newName = "${newStem}_$suffixCounter$extension"
            $destinationPath = Join-Path $item.DirectoryName $newName
            $suffixCounter++
        }
        [void]$plannedDestinations.Add($destinationPath.ToLowerInvariant())

        $status = if ($newStem -match 'PLATZHALTER') { 'umbenannt mit Platzhalter' } else { 'umbenannt' }

        if ($Apply) {
            Rename-Item -Path $item.FullName -NewName $newName

            if ($matchingSource) {
                foreach ($resolvedSourcePath in (Resolve-SourcePaths -PathValue $matchingSource.path)) {
                    if ($destinationPath.StartsWith($resolvedSourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $relativePath = Get-DocFlowRelativePath -BasePath $resolvedSourcePath -FullPath $destinationPath
                        $sourceKey = ("$($matchingSource.path)|$relativePath").ToLowerInvariant()
                        $state.processed[$sourceKey] = [ordered]@{
                            source = $destinationPath
                            targets = @($destinationPath)
                            processedAt = (Get-Date).ToString('o')
                            migriert = $true
                        }
                    }
                }
            }
        }

        $results += [PSCustomObject]@{ Original = $item.Name; Neu = $newName; Status = $status }
    }

    if ($Apply) {
        Save-State -StatePath $statePath -State $state
    }

    $results | Format-Table -AutoSize

    $placeholderCount = @($results | Where-Object { $_.Status -eq 'umbenannt mit Platzhalter' }).Count
    $renamedCount = @($results | Where-Object { $_.Status -like 'umbenannt*' }).Count

    if ($Apply) {
        Write-Host "$renamedCount Datei(en) umbenannt, davon $placeholderCount mit mindestens einem Platzhalter."
    } else {
        Write-Host "Vorschau (nichts wurde veraendert): $renamedCount Datei(en) wuerden umbenannt, davon $placeholderCount mit mindestens einem Platzhalter. Zum tatsaechlichen Umbenennen -Apply angeben."
    }
} finally {
    if ($lockPath -and $lockAcquired) {
        Unlock-DocFlowRun -LockPath $lockPath
    }
}
