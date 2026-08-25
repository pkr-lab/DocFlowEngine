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
        throw "Konfiguration muss mindestens einen Eintrag unter 'targets' enthalten."
    }

    if (-not $config.namingConventions) {
        throw "Konfiguration muss mindestens eine Regel unter 'namingConventions' enthalten."
    }

    if (-not $config.stateFile) {
        $config.stateFile = './.docflow-state.json'
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

    # "Korrigiert"-Rücklauf: Ausbilder markiert eine geprüfte Datei im
    # aufgabenRoot-Baum mit einem Kürzel-Suffix (z. B. "_k-pke"); DocFlowEngine
    # kopiert sie daraufhin in <Schülerordner>/<korrigiertFolderName>/ zurück.
    # Standardmäßig deaktiviert, bis reviewMarker in der Config explizit gesetzt wird.
    if (-not $config.reviewMarker) {
        $config.reviewMarker = @{ enabled = $false }
    }
    if (-not $config.reviewMarker.ContainsKey('enabled')) {
        $config.reviewMarker.enabled = $false
    }
    if (-not $config.reviewMarker.pattern) {
        $config.reviewMarker.pattern = '_k-(?<kuerzel>[A-Za-z]{3})$'
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
        $config.unknownKuerzelHint.message = 'Die Datei "{fileName}" wurde mit dem Kürzel "{kuerzel}" markiert, aber diesem Kürzel ist noch kein Schülerordner bekannt (kuerzel-routes.txt). Bitte prüfen, ob das Kürzel korrekt ist, oder den Schüler einmal regulär hochladen lassen, damit das Kürzel automatisch registriert wird.'
    }

    # Multi-Machine-Betrieb (siehe MULTI-MACHINE-SETUP.md): Lock-Datei
    # verhindert, dass zwei Rechner gleichzeitig in dieselbe (geteilte)
    # State-/Registry-Datei schreiben. Ohne konfigurierten lockFile-Pfad
    # bleibt das Verhalten wie bisher (kein Locking).
    if (-not $config.ContainsKey('lockFile')) {
        $config.lockFile = $null
    }
    if (-not $config.lockTimeoutMinutes) {
        $config.lockTimeoutMinutes = 15
    }

    return $config
}
