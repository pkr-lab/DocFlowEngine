# Logging in DocFlowEngine

DocFlowEngine unterstützt konfigurierbare Protokollierung über die Datei `config/docflow-config.psd1`.

## Log-Level

- `Trace` - sehr ausführliche Informationen
- `Debug` - Diagnoseinformationen zur Fehleranalyse
- `Info` - normale Laufzeitinformationen
- `Warning` - Hinweise auf ungewöhnliche, aber nicht kritische Zustände
- `Error` - Fehler, die zum Abbruch führen

## Beispielkonfiguration

```powershell
log = @{
    level = 'Info'
    file  = './docflow.log'
}
```

## Verhalten

- `Write-Log` schreibt immer in die Konsole.
- Bei vorhandenem `log.file` wird dieselbe Nachricht zusätzlich in diese Datei geschrieben.
- Bei `-DryRun` werden keine Dateien kopiert oder Verzeichnisse erstellt, aber die geplanten Schritte werden protokolliert.
