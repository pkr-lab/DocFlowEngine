# DocFlowEngine

## Projektübersicht

Dieses Projekt dient der Überwachung von Quellordnern, der Erkennung neuer Dokumente, der automatischen Umbenennung nach definierten Regeln und der Kopie in Zielordner. Die Konfiguration soll flexibel sein und sowohl Filter für Dateitypen als auch Logging-Optionen unterstützen.

## Erste Schritte

1. Passe die Konfiguration in `config/docflow-config.psd1` an.
2. Führe das Skript im DryRun-Modus aus, um die geplanten Aktionen zu prüfen:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1 -DryRun
   # oder mit Windows PowerShell 5.1:
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\DocFlowEngine.ps1 -DryRun
   ```
3. Wenn alles passt, führe es ohne `-DryRun` aus:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1
   # oder mit Windows PowerShell 5.1:
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\DocFlowEngine.ps1
   ```

## Voraussetzungen

- **PowerShell 7+** oder **Windows PowerShell 5.1** (bereits auf jedem Windows vorinstalliert) – beide werden gleichwertig unterstützt, keine Installation und keine Admin-Rechte nötig
- **Unterstützte Plattformen**: Windows, macOS, Linux (PowerShell 7+); Windows PowerShell 5.1 nur unter Windows
- **Keine externen Module nötig**: Die Konfiguration liegt als PowerShell-Data-Datei (`.psd1`) vor und wird mit dem eingebauten `Import-PowerShellDataFile` gelesen (verfügbar seit PowerShell 5.0) – dadurch funktioniert alles rein mit Bordmitteln, ganz ohne `Install-Module`

### PowerShell installieren (ohne Admin-Rechte möglich, optional)

```bash
# macOS mit Homebrew
brew install powershell

# Linux (Ubuntu/Debian)
sudo apt-get install -y powershell

# Windows: Chocolatey
choco install powershell-core
```

## Dateien

- `config/docflow-config.psd1` - PowerShell-Data-Konfiguration mit Quellen, Zielen und Umbenennungsregeln
- `scripts/DocFlowEngine.ps1` - Skript-Wrapper, der das modulare `DocFlowEngine.psm1` ausführt
- `scripts/DocFlowEngine.psm1` - PowerShell-Modul mit der eigentlichen Logik
- `tests/DocFlowEngine.Tests.ps1` - Pester-Tests für Konfiguration, Benennung und Kopieren
- `.docflow-state.json` - Statusdatei, die bereits verarbeitete Dateien speichert

## Beispiel-Workflow

### Szenario: Schülermaterial aus SharePoint sortieren

Schüler laden Aufgaben über SharePoint (per OneDrive synchronisiert) hoch. Aufgaben-Dateien
folgen dem Schema `<initialen>_<praefix>_<suffix>_<aufgabennummer>` (z. B. `pke_Java_Suffix_abc.pdf`)
und werden nach `docs/Aufgaben/<Präfix>/<Suffix>/` sortiert. Alle anderen Dateien (z. B. datierte
Rechnungen/Berichte) landen wie gewohnt in `docs/archive/`.

**Verzeichnisstruktur vor Ausführung:**
```
C:/Users/p0*/OneDrive - D*/SharePoint/
├── 2026-06-20 Invoice.pdf
├── 2026-06-22 Report.pdf
├── Unsorted.pdf
└── pke_Java_Suffix_abc.pdf
```

**Konfiguration (`config/docflow-config.psd1`):**
```powershell
@{
    sources = @(
        @{
            path            = 'C:/Users/p0*/OneDrive - D*/SharePoint'
            recursive       = $true
            includePatterns = @('*.pdf', '*.docx', '*.doc', '*.xlsx')
        }
    )

    targets = @(
        @{
            path               = 'C:/Users/p0*/OneDrive - D*/SharePoint/SchuelerMaterial/docs/archive'
            createIfMissing    = $true
            preserveSubfolders = $false
        }
    )

    aufgabenRoot = 'C:/Users/p0*/OneDrive - D*/SharePoint/SchuelerMaterial/docs/Aufgaben'

    namingConventions = @(
        @{
            name        = 'Initials-Praefix-Suffix-Aufgabe'
            description = 'Format initialen_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc). Das Upload-Datum wird vorangestellt.'
            match       = '^(?<initials>[A-Za-z]+)_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename      = '{date}_{initials}_{praefix}_{suffix}_{aufgabennummer}'
        },
        @{
            name        = 'Date-prefix'
            description = 'Dateien mit Datumspräfix behalten dieses'
            match       = '^(?<date>\d{4}-\d{2}-\d{2})\s+(?<name>.+)$'
            rename      = '{date}_{name}'
        }
    )

    projectRoutesFile = './config/project-routes.txt'

    defaultNameFormat = '{timestamp}_{originalName}'
    stateFile         = './.docflow-state.json'

    log = @{
        level = 'Info'
        file  = './docflow.log'
    }
}
```

**Ausführung:**
```powershell
# 1. Vorschau (DryRun-Modus)
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1 -DryRun

# Output:
# [2026-06-25 10:30:15] [Info] Lade Konfiguration: .\config\docflow-config.psd1
# [2026-06-25 10:30:15] [Info] Gefundene Dateien in '...SharePoint': 4
# [2026-06-25 10:30:15] [Info] [DryRun] Datei würde kopiert: ...2026-06-20 Invoice.pdf -> ...archive/2026-06-20_Invoice.pdf
# [2026-06-25 10:30:15] [Info] [DryRun] Datei würde kopiert: ...2026-06-22 Report.pdf -> ...archive/2026-06-22_Report.pdf
# [2026-06-25 10:30:15] [Info] [DryRun] Datei würde kopiert: ...Unsorted.pdf -> ...archive/20260625103015_Unsorted.pdf
# [2026-06-25 10:30:15] [Info] [DryRun] Datei würde kopiert: ...pke_Java_Suffix_abc.pdf -> ...Aufgaben/Java/Suffix/20260625_pke_Java_Suffix_abc.pdf

# 2. Tatsächliche Ausführung
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1

# Output:
# [2026-06-25 10:30:15] [Info] Lade Konfiguration: .\config\docflow-config.psd1
# [2026-06-25 10:30:15] [Info] Gefundene Dateien in '...SharePoint': 4
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...2026-06-20 Invoice.pdf -> ...archive/2026-06-20_Invoice.pdf
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...2026-06-22 Report.pdf -> ...archive/2026-06-22_Report.pdf
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...Unsorted.pdf -> ...archive/20260625103015_Unsorted.pdf
# [2026-06-25 10:30:15] [Info] Neuer Suffix erkannt und in Registry aufgenommen: 'Suffix'
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...pke_Java_Suffix_abc.pdf -> ...Aufgaben/Java/Suffix/20260625_pke_Java_Suffix_abc.pdf
# [2026-06-25 10:30:15] [Info] Verarbeitung abgeschlossen.
```

**Verzeichnisstruktur nach Ausführung:**
```
C:/Users/p0*/OneDrive - D*/SharePoint/SchuelerMaterial/
├── docs/
│   ├── Aufgaben/
│   │   ├──Java
│   │   │  └──Suffix
│   │   │     └──20260625_pke_Java_Suffix_abc.pdf
│   │   ├──Python
│   │   ├──SQL
│   │   ├──Netzwerktechnik
│   │   └──Zahlensysteme
│   └── archive/
│       ├── 2026-06-20_Invoice.pdf
│       ├── 2026-06-22_Report.pdf
│       └── 20260625103015_Unsorted.pdf
├── .docflow-state.json (speichert verarbeitete Dateien)
└── docflow.log
```

Neu erkannte Präfixe/Suffixe (hier `Suffix`) werden automatisch in `config/project-routes.txt`
festgehalten, sodass dort jederzeit alle bisher aufgetretenen Werte nachvollziehbar sind.

**Wiederholte Ausführung:** Beim nächsten Lauf werden diese Dateien nicht erneut kopiert, da sie in `.docflow-state.json` gespeichert sind. Bereits sortierte Dateien unterhalb von `targets`/`aufgabenRoot` werden beim Scannen der Quelle automatisch ausgeschlossen, auch wenn Quell- und Zielordner denselben übergeordneten Pfad teilen.

### Regelmäßige Automatisierung

**Windows: Geplante Aufgabe (keine Admin-Rechte nötig für User Tasks):**
```powershell
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\path\to\DocFlowEngine\scripts\DocFlowEngine.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 08:00
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DocFlowEngine" -Description "Automated document processing"
```

**macOS/Linux: Cron (ohne Admin-Rechte):**
```bash
# Crontab öffnen
crontab -e

# Beispiel: Täglich um 08:00 Uhr
0 8 * * * /usr/local/bin/pwsh -NoProfile -ExecutionPolicy Bypass -File ~/DocFlowEngine/scripts/DocFlowEngine.ps1 >> ~/DocFlowEngine/cron.log 2>&1
```

### Troubleshooting

| Problem | Lösung |
|---------|-----------|
| `pwsh: command not found` | Entweder PowerShell 7+ installieren (siehe Voraussetzungen) oder `powershell.exe` (Windows PowerShell 5.1) verwenden – beide funktionieren gleichwertig |
| `Konfigurationsdatei '...' wurde nicht gefunden` | Prüfe, ob `-ConfigPath` auf eine `.psd1`-Datei zeigt (nicht mehr `.yml`) |
| Fehler beim Parsen der Konfiguration | `config/docflow-config.psd1` muss gültige PowerShell-Hashtable-Syntax sein (`@{ key = 'value' }`); mit `Import-PowerShellDataFile -Path .\config\docflow-config.psd1` lässt sich das isoliert testen |
| Dateien werden nicht kopiert | Nutze `-DryRun`, prüfe die Log-Ausgabe, überprüfe Pfade und Datei-Muster in der Konfiguration |
| `.docflow-state.json` gelöscht | Beim nächsten Lauf wird eine neue Zustandsdatei erstellt; Dateien können dann erneut kopiert werden |
| Keine Schreibrechte im Zielordner | Prüfe Ordnerberechtigungen; DocFlowEngine benötigt nur Schreibrechte im Zielordner, nicht im Quellordner |

## Dokumentation

- `docs/Configuration.md` - Konfigurationsoptionen und Beispielstruktur
- `docs/Module-Reference.md` - Funktionsreferenz und Abhängigkeiten von `DocFlowEngine.psm1`
- `docs/Logging.md` - Logging-Verhalten und Log-Level
- `docs/Testing.md` - Testausführung mit Pester
- `docs/Admin-Requirements.md` - Admin-Rechte und Sicherheitsanforderungen
- `docs/Abschlussbericht.md` - Abschlussbericht zur PowerShell-5.1-Kompatibilität inkl. Quellenbelegen

## Sicherheit & Admin-Rechte

- **Keine Admin-Rechte erforderlich** für die Ausführung des Skripts
- `-ExecutionPolicy Bypass` gilt nur für diesen Prozess, nicht systemweit
- Zugriffsrechte benötigt: Lesezugriff auf Quellordner, Schreibzugriff auf Zielordner
- Zustandsdatei wird im aktuellen Verzeichnis gespeichert (muss schreibbar sein)
- Log-Datei wird im konfigurierten Pfad gespeichert (Verzeichnis muss existieren oder `createIfMissing` setzen)
