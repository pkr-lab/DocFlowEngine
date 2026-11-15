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

function Get-DocFlowConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Config,
        [Parameter(Mandatory)] [string]$Name
    )

    if (-not $Config[$Name]) {
        $Config[$Name] = @{}
    }

    return $Config[$Name]
}

function Set-DocFlowDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Section,
        [hashtable]$IfMissing = @{},
        [hashtable]$IfEmpty = @{}
    )

    foreach ($key in $IfMissing.Keys) {
        if (-not $Section.ContainsKey($key)) {
            $Section[$key] = $IfMissing[$key]
        }
    }

    foreach ($key in $IfEmpty.Keys) {
        if (-not $Section[$key]) {
            $Section[$key] = $IfEmpty[$key]
        }
    }
}

function Import-DocFlowConfig {
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

    Set-DocFlowDefaults -Section $config -IfEmpty @{
        defaultNameFormat = '{timestamp}_{originalName}'
        stateFile = './.docflow-state.json'
        stateRetentionYears = 3
        lockTimeoutMinutes = 15
    } -IfMissing @{
        minFileAgeMinutes = 2
        projectRoutesSeedFile = './config/project-routes.txt'
        lockFile = $null
    }

    if (-not $config.log) {
        $config.log = @{ level = 'Info'; file = './docflow.log' }
    }

    Set-DocFlowDefaults -Section (Get-DocFlowConfigSection -Config $config -Name 'namingConventionHint') -IfMissing @{ enabled = $true } -IfEmpty @{
        fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'
        message = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema (initialen_praefix_suffix_aufgabennummer). Bitte benenne die Datei entsprechend um und lade sie erneut hoch.'
    }

    Set-DocFlowDefaults -Section (Get-DocFlowConfigSection -Config $config -Name 'duplicateHint') -IfMissing @{ enabled = $true } -IfEmpty @{
        fileNameSuffix = '.BEREITS-ABGEGEBEN.txt'
        message = 'Deine Datei "{fileName}" wurde bereits abgegeben. Falls es sich um eine neue Version handelt, benenne sie bitte mit Versionsangabe um, z. B. "{suggestedName}", und lade sie erneut hoch.'
    }

    Set-DocFlowDefaults -Section (Get-DocFlowConfigSection -Config $config -Name 'copyRetry') -IfMissing @{ count = 2; delaySeconds = 5 }

    Set-DocFlowDefaults -Section (Get-DocFlowConfigSection -Config $config -Name 'reviewMarker') -IfMissing @{ enabled = $false } -IfEmpty @{
        pattern = $Script:DefaultReviewMarkerPattern
        korrigiertFolderName = $Script:DefaultKorrigiertFolderName
        kuerzelRoutesFile = './config/kuerzel-routes.txt'
    }

    Set-DocFlowDefaults -Section (Get-DocFlowConfigSection -Config $config -Name 'unknownKuerzelHint') -IfMissing @{ enabled = $true } -IfEmpty @{
        message = 'Die Datei "{fileName}" ist als Korrektur markiert, aber für das im Dateinamen erkannte Kürzel "{kuerzel}" ist noch kein Schülerordner bekannt (kuerzel-routes.txt). Bitte prüfen, oder den Schüler einmal regulär hochladen lassen, damit das Kürzel automatisch registriert wird.'
    }

    $hintPatterns = @("*$($config.namingConventionHint.fileNameSuffix)", "*$($config.duplicateHint.fileNameSuffix)", "*$Script:UnknownKuerzelHintSuffix")
    foreach ($source in @($config.sources)) {
        $excludes = @($source.excludePatterns | Where-Object { $_ })
        foreach ($hintPattern in $hintPatterns) {
            if ($excludes -notcontains $hintPattern) {
                $excludes += $hintPattern
            }
        }
        $source.excludePatterns = $excludes
    }

    Expand-DocFlowConfigPaths -Config $config

    return $config
}
