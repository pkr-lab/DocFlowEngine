function ConvertTo-DocFlowKuerzelByFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable]$KuerzelRoutes
    )

    $kuerzelByFolder = @{}
    foreach ($kuerzel in $KuerzelRoutes.Keys) {
        $folder = $KuerzelRoutes[$kuerzel].TrimEnd('\', '/')
        if (-not $kuerzelByFolder.ContainsKey($folder)) {
            $kuerzelByFolder[$folder] = $kuerzel
        }
    }

    return $kuerzelByFolder
}

function Get-DocFlowFolderInitials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.IO.FileInfo[]]$Files,
        [Parameter(Mandatory)] [array]$Rules,
        $Registry = $null,
        [hashtable]$KuerzelByFolder = @{},
        [string]$Placeholder = 'PLATZHALTER'
    )

    $initialsByFolder = @{}
    foreach ($group in ($Files | Group-Object -Property DirectoryName)) {
        $folder = $group.Name.TrimEnd('\', '/')
        $compliantVotes = @{}
        $guessedVotes = @{}
        foreach ($file in $group.Group) {
            $stemName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $parts = Get-DocFlowSubmissionParts -Name $stemName -Rules $Rules
            if ($parts) {
                $compliantVotes[$parts.Initials] = 1 + [int]$compliantVotes[$parts.Initials]
                continue
            }
            $guess = Get-DocFlowNameProposal -Name $stemName -Rules $Rules -Registry $Registry -Placeholder $Placeholder
            if ($guess.Initials -and $guess.Initials -ne $Placeholder -and ($guess.Praefix -ne $Placeholder -or $guess.Suffix -ne $Placeholder)) {
                $guessedVotes[$guess.Initials] = 1 + [int]$guessedVotes[$guess.Initials]
            }
        }

        if ($compliantVotes.Count -gt 0) {
            $initials = ($compliantVotes.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key
            $initialsByFolder[$folder] = [PSCustomObject]@{ Initials = $initials; Source = 'aus regelkonformen Dateien im Ordner' }
        } elseif ($KuerzelByFolder.ContainsKey($folder)) {
            $initialsByFolder[$folder] = [PSCustomObject]@{ Initials = $KuerzelByFolder[$folder]; Source = 'aus der Kürzel-Registry' }
        } elseif ($guessedVotes.Count -eq 1) {
            $initialsByFolder[$folder] = [PSCustomObject]@{ Initials = @($guessedVotes.Keys)[0]; Source = 'aus anderen Dateinamen im Ordner' }
        }
    }

    return $initialsByFolder
}

function Undo-DocFlowRename {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath)) {
        throw "Undo-Datei '$ReportPath' wurde nicht gefunden."
    }

    $undoRows = @(Import-Csv -LiteralPath $ReportPath -Delimiter ';' | Where-Object { $_.Ausgefuehrt -eq 'ja' })
    [array]::Reverse($undoRows)
    $restored = 0
    foreach ($row in $undoRows) {
        if (-not (Test-Path -LiteralPath $row.NeuerPfad)) {
            Write-Warning "Nicht mehr vorhanden, übersprungen: '$($row.NeuerPfad)'"
            continue
        }
        if (Test-Path -LiteralPath $row.AlterPfad) {
            Write-Warning "Alter Name ist bereits wieder belegt, übersprungen: '$($row.AlterPfad)'"
            continue
        }
        try {
            Rename-Item -LiteralPath $row.NeuerPfad -NewName (Split-Path -Path $row.AlterPfad -Leaf) -ErrorAction Stop
            $restored++
        } catch {
            Write-Warning "Konnte '$($row.NeuerPfad)' nicht zurückbenennen: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{ Restored = $restored; Total = $undoRows.Count }
}
