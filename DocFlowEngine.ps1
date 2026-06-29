param(
    [string]$ConfigPath = ".\config\docflow-config.yml",
    [switch]$DryRun
)

$modulePath = Join-Path $PSScriptRoot 'DocFlowEngine.psm1'
if (-not (Test-Path $modulePath)) {
    throw "Moduldatei '$modulePath' wurde nicht gefunden."
}

Import-Module -Name $modulePath -Force
Invoke-DocFlowEngine -ConfigPath $ConfigPath -DryRun:$DryRun
