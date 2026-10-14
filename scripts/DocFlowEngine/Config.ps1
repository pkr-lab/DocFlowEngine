function Resolve-DocFlowPathVariables {
    [CmdletBinding()]
    param(
        [hashtable]$Paths
    )

    $resolved = @{}
    if (-not $Paths) {
        return $resolved
    }

    $resolving = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $resolveOne = $null
    $resolveOne = {
        param([string]$Name)

        if ($resolved.ContainsKey($Name)) {
            return $resolved[$Name]
        }

        if (-not $Paths.ContainsKey($Name)) {
            throw "Pfad-Variable '{$Name}' ist in 'paths' nicht definiert."
        }

        if (-not $resolving.Add($Name)) {
            throw "Zirkulärer Verweis in 'paths' bei '{$Name}'."
        }

        $value = [string]$Paths[$Name]
        foreach ($match in [regex]::Matches($value, '\{(?<name>[A-Za-z0-9_]+)\}')) {
            $innerName = $match.Groups['name'].Value
            $value = $value.Replace($match.Value, (& $resolveOne $innerName))
        }

        [void]$resolving.Remove($Name)
        $resolved[$Name] = $value
        return $value
    }

    foreach ($name in @($Paths.Keys)) {
        [void](& $resolveOne $name)
    }

    return $resolved
}

function Expand-DocFlowPathValue {
    [CmdletBinding()]
    param(
        [AllowNull()] [AllowEmptyString()] [string]$Value,
        [Parameter(Mandatory)] [hashtable]$PathVariables,
        [string]$FieldName = ''
    )

    if (-not $Value) {
        return $Value
    }

    $result = $Value
    foreach ($match in [regex]::Matches($Value, '\{(?<name>[A-Za-z0-9_]+)\}')) {
        $name = $match.Groups['name'].Value
        if (-not $PathVariables.ContainsKey($name)) {
            throw "Pfad-Variable '{$name}' in '$FieldName' ist in 'paths' nicht definiert."
        }
        $result = $result.Replace($match.Value, $PathVariables[$name])
    }

    return $result
}

function Expand-DocFlowConfigPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Config
    )

    $variables = Resolve-DocFlowPathVariables -Paths $Config.paths

    foreach ($source in @($Config.sources)) {
        $source.path = Expand-DocFlowPathValue -Value $source.path -PathVariables $variables -FieldName 'sources.path'
    }

    foreach ($target in @($Config.targets)) {
        $target.path = Expand-DocFlowPathValue -Value $target.path -PathVariables $variables -FieldName 'targets.path'
    }

    foreach ($key in @('aufgabenRoot', 'projectRoutesFile', 'projectRoutesSeedFile', 'stateFile', 'lockFile')) {
        if ($Config.ContainsKey($key)) {
            $Config[$key] = Expand-DocFlowPathValue -Value $Config[$key] -PathVariables $variables -FieldName $key
        }
    }

    if ($Config.log) {
        $Config.log.file = Expand-DocFlowPathValue -Value $Config.log.file -PathVariables $variables -FieldName 'log.file'
    }

    if ($Config.reviewMarker) {
        $Config.reviewMarker.kuerzelRoutesFile = Expand-DocFlowPathValue -Value $Config.reviewMarker.kuerzelRoutesFile -PathVariables $variables -FieldName 'reviewMarker.kuerzelRoutesFile'
    }
}

function Load-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Konfigurationsdatei '$Path' wurde nicht gefunden."
    }

    $config = Import-PowerShellDataFile -Path $Path

    if (-not $config.sources) {
        throw "Konfiguration muss mindestens einen Eintrag unter 'sources' enthalten."
    }

    if (-not $config.targets) {
        $config.targets = @()
    }

    if ($config.targets.Count -eq 0 -and -not $config.aufgabenRoot) {
        throw "Konfiguration braucht 'aufgabenRoot' oder mindestens einen Eintrag unter 'targets'."
    }

    if (-not $config.namingConventions) {
        throw "Konfiguration muss mindestens eine Regel unter 'namingConventions' enthalten."
    }

    if (-not $config.defaultNameFormat) {
        $config.defaultNameFormat = '{timestamp}_{originalName}'
    }

    if (-not $config.stateFile) {
        $config.stateFile = './.docflow-state.json'
    }
    if (-not $config.stateRetentionYears) {
        $config.stateRetentionYears = 3
    }

    if (-not $config.log) {
        $config.log = @{ level = 'Info'; file = './docflow.log' }
    }

    if (-not $config.namingConventionHint) {
        $config.namingConventionHint = @{}
    }
    if (-not $config.namingConventionHint.ContainsKey('enabled')) {
        $config.namingConventionHint.enabled = $true
    }
    if (-not $config.namingConventionHint.fileNameSuffix) {
        $config.namingConventionHint.fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'
    }
    if (-not $config.namingConventionHint.message) {
        $config.namingConventionHint.message = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema (initialen_praefix_suffix_aufgabennummer). Bitte benenne die Datei entsprechend um und lade sie erneut hoch.'
    }

    if (-not $config.duplicateHint) {
        $config.duplicateHint = @{}
    }
    if (-not $config.duplicateHint.ContainsKey('enabled')) {
        $config.duplicateHint.enabled = $true
    }
    if (-not $config.duplicateHint.fileNameSuffix) {
        $config.duplicateHint.fileNameSuffix = '.BEREITS-ABGEGEBEN.txt'
    }
    if (-not $config.duplicateHint.message) {
        $config.duplicateHint.message = 'Deine Datei "{fileName}" wurde bereits abgegeben. Falls es sich um eine neue Version handelt, benenne sie bitte mit Versionsangabe um, z. B. "{suggestedName}", und lade sie erneut hoch.'
    }

    if (-not $config.ContainsKey('minFileAgeMinutes')) {
        $config.minFileAgeMinutes = 2
    }

    if (-not $config.copyRetry) {
        $config.copyRetry = @{}
    }
    if (-not $config.copyRetry.ContainsKey('count')) {
        $config.copyRetry.count = 2
    }
    if (-not $config.copyRetry.ContainsKey('delaySeconds')) {
        $config.copyRetry.delaySeconds = 5
    }

    $hintPatterns = @("*$($config.namingConventionHint.fileNameSuffix)", "*$($config.duplicateHint.fileNameSuffix)", '*.KUERZEL-UNBEKANNT.txt')
    foreach ($source in @($config.sources)) {
        $excludes = @($source.excludePatterns | Where-Object { $_ })
        foreach ($hintPattern in $hintPatterns) {
            if ($excludes -notcontains $hintPattern) {
                $excludes += $hintPattern
            }
        }
        $source.excludePatterns = $excludes
    }

    if (-not $config.reviewMarker) {
        $config.reviewMarker = @{ enabled = $false }
    }
    if (-not $config.reviewMarker.ContainsKey('enabled')) {
        $config.reviewMarker.enabled = $false
    }
    if (-not $config.reviewMarker.pattern) {
        $config.reviewMarker.pattern = '_k-[A-Za-z0-9]+$'
    }
    if (-not $config.reviewMarker.korrigiertFolderName) {
        $config.reviewMarker.korrigiertFolderName = 'Korrigiert'
    }
    if (-not $config.reviewMarker.kuerzelRoutesFile) {
        $config.reviewMarker.kuerzelRoutesFile = './config/kuerzel-routes.txt'
    }

    if (-not $config.unknownKuerzelHint) {
        $config.unknownKuerzelHint = @{}
    }
    if (-not $config.unknownKuerzelHint.ContainsKey('enabled')) {
        $config.unknownKuerzelHint.enabled = $true
    }
    if (-not $config.unknownKuerzelHint.message) {
        $config.unknownKuerzelHint.message = 'Die Datei "{fileName}" ist als Korrektur markiert, aber für das im Dateinamen erkannte Kürzel "{kuerzel}" ist noch kein Schülerordner bekannt (kuerzel-routes.txt). Bitte prüfen, oder den Schüler einmal regulär hochladen lassen, damit das Kürzel automatisch registriert wird.'
    }

    if (-not $config.ContainsKey('projectRoutesSeedFile')) {
        $config.projectRoutesSeedFile = './config/project-routes.txt'
    }

    if (-not $config.ContainsKey('lockFile')) {
        $config.lockFile = $null
    }
    if (-not $config.lockTimeoutMinutes) {
        $config.lockTimeoutMinutes = 15
    }

    Expand-DocFlowConfigPaths -Config $config

    return $config
}
