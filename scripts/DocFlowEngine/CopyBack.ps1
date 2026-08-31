function Get-KuerzelRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $routes = @{}

    if (-not (Test-Path $Path)) {
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

        $kuerzel = $trimmed.Substring(0, $separatorIndex).Trim().ToLowerInvariant()
        $studentPath = $trimmed.Substring($separatorIndex + 1).Trim()
        if ($kuerzel -and $studentPath) {
            $routes[$kuerzel] = $studentPath
        }
    }

    return $routes
}

function Register-Kuerzel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Routes,
        [string]$RoutesFilePath,
        [Parameter(Mandatory)] [string]$Kuerzel,
        [Parameter(Mandatory)] [string]$SourcePath
    )

    $key = $Kuerzel.ToLowerInvariant()
    if ($Routes.ContainsKey($key)) {
        return
    }

    $Routes[$key] = $SourcePath
    Write-Log -Level Info -Message "Neues Kürzel erkannt und in Kuerzel-Registry aufgenommen: '$Kuerzel' -> '$SourcePath'"

    if (-not $RoutesFilePath) {
        return
    }

    if ($Script:DryRun) {
        Write-Log -Level Info -Message "[DryRun] Kuerzel-Registry '$RoutesFilePath' würde aktualisiert: $Kuerzel=$SourcePath"
        return
    }

    $directory = Split-Path -Path $RoutesFilePath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Add-Content -Path $RoutesFilePath -Value "$key=$SourcePath"
}

function Copy-ReviewedFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AufgabenRoot,
        [Parameter(Mandatory)] [hashtable]$ReviewMarker,
        [Parameter(Mandatory)] [hashtable]$KuerzelRoutes,
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [array]$Rules,
        [hashtable]$UnknownKuerzelHint = $null
    )

    if (-not $ReviewMarker.enabled) {
        return
    }

    if (-not (Test-Path $AufgabenRoot)) {
        return
    }

    $korrigiertFolderName = $ReviewMarker.korrigiertFolderName
    if (-not $korrigiertFolderName) {
        $korrigiertFolderName = 'Korrigiert'
    }

    $pattern = [regex]::new($ReviewMarker.pattern)
    $items = Get-ChildItem -Path $AufgabenRoot -File -Recurse -ErrorAction SilentlyContinue

    foreach ($item in $items) {
        if (Test-DocFlowInsideNamedFolder -DirectoryName $item.DirectoryName -FolderName $korrigiertFolderName) {
            continue
        }

        $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
        $markerMatch = $pattern.Match($nameWithoutExtension)
        if (-not $markerMatch.Success) {
            continue
        }

        $reviewKey = $item.FullName.ToLowerInvariant()
        if ($State.reviewedFiles.ContainsKey($reviewKey)) {
            continue
        }

        $originalStem = $nameWithoutExtension.Substring(0, $markerMatch.Index) -replace '^\d{8}_', ''
        $kuerzel = Get-FileInitialsFromName -Name $originalStem -Rules $Rules

        if ($kuerzel -and $KuerzelRoutes.ContainsKey($kuerzel.ToLowerInvariant())) {
            $studentFolder = $KuerzelRoutes[$kuerzel.ToLowerInvariant()]
            $korrigiertFolder = Join-Path $studentFolder $korrigiertFolderName

            if (-not (Test-Path $korrigiertFolder)) {
                if ($Script:DryRun) {
                    Write-Log -Level Info -Message "[DryRun] Verzeichnis würde erstellt: $korrigiertFolder"
                } else {
                    New-Item -ItemType Directory -Path $korrigiertFolder -Force | Out-Null
                }
            }

            $destinationPath = Join-Path $korrigiertFolder $item.Name

            if ($Script:DryRun) {
                Write-Log -Level Info -Message "[DryRun] Korrigierte Datei würde zurückkopiert: '$($item.FullName)' -> '$destinationPath'"
            } else {
                Write-Log -Level Info -Message "Kopiere korrigierte Datei zurück: '$($item.FullName)' -> '$destinationPath'"
                Copy-Item -Path $item.FullName -Destination $destinationPath -Force
            }

            $State.reviewedFiles[$reviewKey] = [ordered]@{
                source = $item.FullName
                target = $destinationPath
                kuerzel = $kuerzel.ToLowerInvariant()
                processedAt = (Get-Date).ToString('o')
            }
        } else {
            Write-Log -Level Warning -Message "Kein Schülerordner für '$($item.Name)' ermittelbar (erkanntes Kürzel aus dem Dateinamen: '$kuerzel') - Rückkopie übersprungen."

            if ($UnknownKuerzelHint -and $UnknownKuerzelHint.enabled) {
                $hintPath = Join-Path $item.DirectoryName "$($item.Name).KUERZEL-UNBEKANNT.txt"
                if (-not (Test-Path $hintPath)) {
                    $context = [ordered]@{
                        fileName = $item.Name
                        kuerzel = if ($kuerzel) { $kuerzel } else { '' }
                    }
                    $message = Expand-Template -Template $UnknownKuerzelHint.message -Context $context
                    if ($Script:DryRun) {
                        Write-Log -Level Info -Message "[DryRun] Hinweis-Datei würde erstellt: '$hintPath'"
                    } else {
                        Set-Content -Path $hintPath -Value $message -Encoding UTF8
                    }
                }
            }
        }
    }
}
