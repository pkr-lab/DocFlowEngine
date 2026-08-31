#Requires -Version 5.1

$Script:DocFlowModuleParts = @(
    'Common.ps1'
    'Config.ps1'
    'State.ps1'
    'Lock.ps1'
    'Naming.ps1'
    'CopyForward.ps1'
    'CopyBack.ps1'
)

foreach ($part in $Script:DocFlowModuleParts) {
    $partPath = Join-Path (Join-Path $PSScriptRoot 'DocFlowEngine') $part
    if (-not (Test-Path $partPath)) {
        throw "Teilmodul '$partPath' wurde nicht gefunden."
    }
    . $partPath
}

function Invoke-DocFlowEngine {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = '.\config\docflow-config.psd1',
        [switch]$DryRun
    )

    $Script:LogLevels = @{ Trace = 0; Debug = 1; Info = 2; Warning = 3; Error = 4 }
    $Script:DryRun = $DryRun

    $config = Load-Config -Path $ConfigPath
    $logLevelValue = $config.log.level
    if ($null -eq $logLevelValue) {
        $logLevelValue = 'Info'
    }
    $logLevelName = $logLevelValue.ToString()
    if (-not $Script:LogLevels.ContainsKey($logLevelName)) {
        $logLevelName = 'Info'
    }

    $Script:CurrentLogLevel = $Script:LogLevels[$logLevelName]
    $Script:LogFilePath = Resolve-PathOrAbsolute -PathValue $config.log.file

    if ($Script:LogFilePath -and -not $DryRun) {
        $logDir = Split-Path -Path $Script:LogFilePath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }

    Write-Log -Level Info -Message "Lade Konfiguration: $ConfigPath"

    $lockPath = $null
    $lockAcquired = $true
    if ($config.lockFile -and -not $DryRun) {
        $lockPath = Resolve-PathOrAbsolute -PathValue $config.lockFile
        $lockAcquired = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes $config.lockTimeoutMinutes
    }

    if (-not $lockAcquired) {
        Write-Log -Level Warning -Message "Verarbeitung übersprungen, da eine andere Instanz aktiv ist."
        return
    }

    try {
        Ensure-TargetDirectories -Targets $config.targets

        $statePath = Resolve-PathOrAbsolute -PathValue $config.stateFile
        $state = Load-State -StatePath $statePath

        $categoryRoutes = if ($config.categoryRoutes) { $config.categoryRoutes } else { @() }

        $aufgabenRoot = $null
        if ($config.aufgabenRoot) {
            $aufgabenRoot = Resolve-PathOrAbsolute -PathValue $config.aufgabenRoot
        }

        $registryFilePath = $null
        $praefixSuffixRegistry = [ordered]@{
            Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Suffixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        if ($config.projectRoutesFile) {
            $registryFilePath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesFile

            if ($config.projectRoutesSeedFile) {
                $seedFilePath = Resolve-PathOrAbsolute -PathValue $config.projectRoutesSeedFile
                Sync-ProjectRoutesFromSeed -SeedPath $seedFilePath -TargetPath $registryFilePath
            }

            $praefixSuffixRegistry = Get-PraefixSuffixRegistry -Path $registryFilePath
        }

        $kuerzelRoutesFilePath = $null
        $kuerzelRoutes = @{}
        if ($config.reviewMarker.kuerzelRoutesFile) {
            $kuerzelRoutesFilePath = Resolve-PathOrAbsolute -PathValue $config.reviewMarker.kuerzelRoutesFile
            $kuerzelRoutes = Get-KuerzelRoutes -Path $kuerzelRoutesFilePath
        }

        $excludePaths = @()
        foreach ($target in $config.targets) {
            $excludePaths += $target.path
        }
        if ($aufgabenRoot) {
            $excludePaths += $aufgabenRoot
        }

        Copy-NewFiles -Sources $config.sources -Targets $config.targets -State $state -Rules $config.namingConventions -DefaultNameFormat $config.defaultNameFormat -CategoryRoutes $categoryRoutes -AufgabenRoot $aufgabenRoot -PraefixSuffixRegistry $praefixSuffixRegistry -RegistryFilePath $registryFilePath -ExcludePaths $excludePaths -NamingConventionHint $config.namingConventionHint -KuerzelRoutes $kuerzelRoutes -KuerzelRoutesFilePath $kuerzelRoutesFilePath -KorrigiertFolderName $config.reviewMarker.korrigiertFolderName

        if ($aufgabenRoot -and $config.reviewMarker.enabled) {
            Copy-ReviewedFiles -AufgabenRoot $aufgabenRoot -ReviewMarker $config.reviewMarker -KuerzelRoutes $kuerzelRoutes -State $state -Rules $config.namingConventions -UnknownKuerzelHint $config.unknownKuerzelHint
        }

        if (-not $DryRun) {
            Save-State -StatePath $statePath -State $state
        }

        Write-Log -Level Info -Message "Verarbeitung abgeschlossen."
    } finally {
        if ($lockPath -and $lockAcquired) {
            Unlock-DocFlowRun -LockPath $lockPath
        }
    }
}

Export-ModuleMember -Function Invoke-DocFlowEngine, Get-TargetFileName, Load-Config, Load-State, Save-State, Get-SourceFiles, Ensure-TargetDirectories, Resolve-PathOrAbsolute, Resolve-SourcePaths, Test-PathExcluded, Expand-Template, Write-Log, Copy-NewFiles, Get-FileCategory, Resolve-CategoryTarget, Get-FileProject, Get-ProjectRoutes, Resolve-ProjectTarget, Get-FilePraefixSuffix, Get-FileInitials, Get-FileInitialsFromName, Get-PraefixSuffixRegistry, Sync-ProjectRoutesFromSeed, Test-DocFlowPraefixSuffixKnown, ConvertTo-DocFlowHashtable, Get-DocFlowRelativePath, Write-NamingConventionHint, Get-KuerzelRoutes, Register-Kuerzel, Copy-ReviewedFiles, Lock-DocFlowRun, Unlock-DocFlowRun, Test-DocFlowLockFresh, Test-DocFlowInsideNamedFolder
