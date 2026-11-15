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

    $Script:DryRun = $DryRun

    $config = Import-DocFlowConfig -Path $ConfigPath
    $logLevelName = [string]$config.log.level
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
        if (@($config.targets).Count -gt 0) {
            Initialize-DocFlowTargetDirectories -Targets $config.targets
        }

        $context = New-DocFlowRunContext -Config $config
        $state = $context.State

        Invoke-DocFlowCopyForward -Config $config -Context $context

        if ($context.AufgabenRoot -and $config.reviewMarker.enabled) {
            Copy-ReviewedFiles -AufgabenRoot $context.AufgabenRoot -ReviewMarker $config.reviewMarker -KuerzelRoutes $context.KuerzelRoutes -State $state -Rules $config.namingConventions -UnknownKuerzelHint $config.unknownKuerzelHint -RetryCount $config.copyRetry.count -RetryDelaySeconds $config.copyRetry.delaySeconds
        }

        if ($config.stateRetentionYears -gt 0) {
            $expiredCount = Remove-DocFlowExpiredState -State $state -RetentionYears $config.stateRetentionYears
            if ($expiredCount -gt 0) {
                if ($DryRun) {
                    Write-Log -Level Info -Message "[DryRun] $expiredCount Zustands-Eintraege aelter als $($config.stateRetentionYears) Jahre wuerden entfernt."
                } else {
                    Write-Log -Level Info -Message "$expiredCount Zustands-Eintraege aelter als $($config.stateRetentionYears) Jahre entfernt."
                }
            }
        }

        if (-not $DryRun) {
            Save-State -StatePath $context.StatePath -State $state
        }

        Write-Log -Level Info -Message "Verarbeitung abgeschlossen."
    } finally {
        if ($lockPath -and $lockAcquired) {
            Unlock-DocFlowRun -LockPath $lockPath
        }
    }
}

Set-Alias -Name Load-Config -Value Import-DocFlowConfig
Set-Alias -Name Load-State -Value Import-DocFlowState
Set-Alias -Name Ensure-TargetDirectories -Value Initialize-DocFlowTargetDirectories

Export-ModuleMember -Alias Load-Config, Load-State, Ensure-TargetDirectories -Function Invoke-DocFlowEngine, Invoke-DocFlowCopyForward, New-DocFlowRunContext, Copy-DocFlowFileWithRetry, Test-DocFlowFileReady, Write-DocFlowHintFile, Remove-DocFlowHintFile, Remove-DocFlowOrphanedHintFiles, Get-DocFlowFileFingerprint, Test-DocFlowSameFileVersion, Get-DocFlowSubmissionParts, Find-DocFlowExistingSubmission, Get-DocFlowSuggestedVersionName, New-DocFlowSubmissionStem, Write-DocFlowDuplicateHint, Get-DocFlowNameProposal, ConvertTo-DocFlowAsciiName, Resolve-DocFlowPathVariables, Expand-DocFlowPathValue, Expand-DocFlowConfigPaths, Get-TargetFileName, Import-DocFlowConfig, Import-DocFlowState, Save-State, Remove-DocFlowExpiredState, Get-SourceFiles, Initialize-DocFlowTargetDirectories, Resolve-PathOrAbsolute, Resolve-SourcePaths, Test-PathExcluded, Expand-Template, Write-Log, Copy-NewFiles, Get-FileCategory, Resolve-CategoryTarget, Get-FilePraefixSuffix, Get-FileInitials, Get-FileInitialsFromName, Get-PraefixSuffixRegistry, Sync-ProjectRoutesFromSeed, Get-DocFlowMigratedFileName, Test-DocFlowPraefixSuffixKnown, ConvertTo-DocFlowHashtable, Get-DocFlowRelativePath, Write-NamingConventionHint, Get-KuerzelRoutes, Register-Kuerzel, Copy-ReviewedFiles, Lock-DocFlowRun, Unlock-DocFlowRun, Test-DocFlowLockFresh, Test-DocFlowInsideNamedFolder