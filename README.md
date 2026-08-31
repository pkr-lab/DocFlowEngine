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

### PowerShell installieren (nur für macOS/Linux nötig - optional)

Auf dem eigentlichen Zielsystem (Windows-Schulrechner) ist **nichts zu installieren**:
Windows PowerShell 5.1 ist auf jedem Windows bereits vorhanden, DocFlowEngine läuft
damit ohne jeden zusätzlichen Schritt. Die folgenden Befehle sind nur für alle, die
DocFlowEngine testweise unter macOS/Linux ausführen möchten (z. B. Entwicklung) -
PowerShell 5.1 selbst existiert dort nicht, PowerShell 7+ ist der Ersatz.

```bash
# macOS mit Homebrew (kein sudo nötig)
brew install powershell

# Linux (Ubuntu/Debian) - benötigt sudo/Admin-Rechte für die Paketinstallation;
# alternativ ganz ohne Admin-Rechte über das offizielle .tar.gz-Archiv
# (https://github.com/PowerShell/PowerShell/releases) in ein Benutzerverzeichnis entpacken
sudo apt-get install -y powershell
```

## Dateien

- `config/docflow-config.psd1` - PowerShell-Data-Konfiguration mit Quellen, Zielen und Umbenennungsregeln
- `config/project-routes.txt` - Startbestand der Präfix/Suffix-Whitelist, von Hand gepflegt und versioniert. Wird bei jedem Lauf automatisch in die geteilte Laufzeit-Kopie synchronisiert (siehe [docs/Konzepte/MULTI-MACHINE-SETUP.md](docs/Konzepte/MULTI-MACHINE-SETUP.md))
- `scripts/DocFlowEngine.ps1` - Skript-Wrapper, der das modulare `DocFlowEngine.psm1` ausführt
- `scripts/Invoke-OneDriveSync.ps1` - Eigenständiges Skript, das vor dem eigentlichen Lauf einen OneDrive-Sync anstößt (siehe "Regelmäßige Automatisierung" unten)
- `scripts/Rename-ExistingAufgaben.ps1` - Eigenständiges, manuell auszuführendes Migrationsskript für bestehende (nicht dem Namensschema folgende) Alt-Dateien (siehe unten)
- `scripts/DocFlowEngine.psm1` - Root-Modul: bindet die Teilmodule unten ein und stellt `Invoke-DocFlowEngine` bereit
- `scripts/DocFlowEngine/Common.ps1` - Logging, Pfadauflösung, generische Hilfsfunktionen
- `scripts/DocFlowEngine/Config.ps1` - Laden und Validieren der Konfiguration inkl. Defaults
- `scripts/DocFlowEngine/State.ps1` - Laden/Speichern der Zustandsdatei
- `scripts/DocFlowEngine/Lock.ps1` - Lock-Datei für den Multi-Machine-Betrieb
- `scripts/DocFlowEngine/Naming.ps1` - Namenskonvention, Umbenennung, Pro-Datei-Hinweise, Präfix/Suffix-Whitelist-Prüfung
- `scripts/DocFlowEngine/CopyForward.ps1` - Quell-Scan und Kopieren neuer Dateien
- `scripts/DocFlowEngine/CopyBack.ps1` - "Korrigiert"-Rücklauf (Kürzel-Registry, Rückkopie geprüfter Dateien)
- `tests/DocFlowEngine.Tests.ps1` - Pester-Tests für Konfiguration, Benennung, Kopieren, Rücklauf und Locking
- `docs/` - Detail-Dokumentation, siehe [Abschnitt "Dokumentation"](#dokumentation) unten
- `.gitignore` - schließt Laufzeitdateien (State, Log, Lock, Pro-Datei-Hinweise) von Git aus
- `.docflow-state.json` - Statusdatei, die bereits verarbeitete Dateien speichert (im Multi-Machine-Betrieb im geteilten Ordner, siehe unten). Einträge älter als `stateRetentionYears` (Default 3 Jahre) werden bei jedem Lauf automatisch entfernt, damit die Datei nicht unbegrenzt wächst

## Beispiel-Workflow

### Szenario: Schülermaterial aus SharePoint sortieren

Schüler laden Aufgaben über SharePoint (per OneDrive synchronisiert) hoch. Aufgaben-Dateien
folgen dem Schema `<initialen>[_v<version>]_<praefix>_<suffix>_<aufgabennummer>` (z. B.
`pke_Java_Arrays_abc.pdf`, bei einer erneuten Abgabe `pke_v2_Java_Arrays_abc.pdf`) und werden nach
`docs/Aufgaben/<Präfix>/<Suffix>/` sortiert. Die Versionsangabe ist optional - ohne sie funktioniert
das Schema wie bisher, mit ihr lassen sich mehrere Abgaben derselben Aufgabe unterscheiden, statt sich
gegenseitig zu überschreiben. Alle anderen Dateien (z. B. datierte Rechnungen/Berichte) landen wie
gewohnt in `docs/archive/`.

**Verzeichnisstruktur vor Ausführung:**
```
C:/Users/p0*/OneDrive - D*/SharePoint/
├── 2026-06-20 Invoice.pdf
├── 2026-06-22 Report.pdf
├── Unsorted.pdf
└── pke_Java_Arrays_abc.pdf
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
            description = 'Format initialen[_v<version>]_praefix_suffix_aufgabennummer (z. B. pke_Java_Arrays_abc oder pke_v2_Java_Arrays_abc). Das Upload-Datum wird vorangestellt.'
            match       = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename      = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
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
# [2026-06-25 10:30:15] [Info] [DryRun] Datei würde kopiert: ...pke_Java_Arrays_abc.pdf -> ...Aufgaben/Java/Arrays/20260625_pke_Java_Arrays_abc.pdf

# 2. Tatsächliche Ausführung
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1

# Output:
# [2026-06-25 10:30:15] [Info] Lade Konfiguration: .\config\docflow-config.psd1
# [2026-06-25 10:30:15] [Info] Gefundene Dateien in '...SharePoint': 4
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...2026-06-20 Invoice.pdf -> ...archive/2026-06-20_Invoice.pdf
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...2026-06-22 Report.pdf -> ...archive/2026-06-22_Report.pdf
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...Unsorted.pdf -> ...archive/20260625103015_Unsorted.pdf
# [2026-06-25 10:30:15] [Info] Kopiere Datei: ...pke_Java_Arrays_abc.pdf -> ...Aufgaben/Java/Arrays/20260625_pke_Java_Arrays_abc.pdf
# [2026-06-25 10:30:15] [Info] Verarbeitung abgeschlossen.
```

**Verzeichnisstruktur nach Ausführung:**
```
C:/Users/p0*/OneDrive - D*/SharePoint/SchuelerMaterial/
├── docs/
│   ├── Aufgaben/
│   │   ├──Java
│   │   │  └──Arrays
│   │   │     └──20260625_pke_Java_Arrays_abc.pdf
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

`Java` und `Arrays` mussten dafür bereits vorab in `config/project-routes.txt` stehen
(`praefix=Java` / `suffix=Arrays`). Ein Präfix oder Suffix, der dort nicht gelistet ist, wird wie
eine falsche Namenskonvention behandelt (siehe nächster Abschnitt). Neue Fächer/Themen werden von
Hand in `config/project-routes.txt` ergänzt (dem versionierten Startbestand im Repo) - DocFlowEngine
kopiert diese Datei bei jedem Lauf automatisch in die unter `projectRoutesFile` konfigurierte,
tatsächlich genutzte Kopie (legt sie beim ersten Mal an, ergänzt bei jedem weiteren Lauf neue
Zeilen aus dem Startbestand). Ein manuelles Kopieren ist nicht mehr nötig; siehe `projectRoutesSeedFile` in
[docs/Configuration.md](docs/Configuration.md).

**Wiederholte Ausführung:** Beim nächsten Lauf werden diese Dateien nicht erneut kopiert, da sie in `.docflow-state.json` gespeichert sind. Bereits sortierte Dateien unterhalb von `targets`/`aufgabenRoot` werden beim Scannen der Quelle automatisch ausgeschlossen, auch wenn Quell- und Zielordner denselben übergeordneten Pfad teilen.

**Falsch benannte Dateien:** Eine Datei unterhalb von `aufgabenRoot` wird in zwei Fällen NICHT kopiert:
1. Der Dateiname passt zu keiner Regel mit `praefix`/`suffix`-Gruppen (z. B. Suffix ganz weggelassen).
2. Der Dateiname passt zwar zum Schema, aber Präfix und/oder Suffix stehen noch nicht in `project-routes.txt` (z. B. Tippfehler wie `Jaava` statt `Java`, oder ein noch nicht angelegtes neues Fach).

In beiden Fällen legt DocFlowEngine direkt neben der Datei einen individuellen Hinweis an (`<Dateiname>.NAMENSKONVENTION-FEHLER.txt`, optional mit `{praefix}`/`{suffix}` in der Meldung), damit bei mehreren betroffenen Dateien im selben Ordner erkennbar bleibt, welche gemeint ist und woran es liegt.

**"Korrigiert"-Rücklauf:** Benennt ein Ausbilder eine geprüfte Datei unterhalb von `aufgabenRoot` um und hängt `_k-<beliebiger Text>` an (z. B. `20260625_pke_Java_Arrays_abc_k-ml.pdf` oder auch `..._k-abc.pdf`), kopiert DocFlowEngine sie beim nächsten Lauf automatisch in einen `Korrigiert`-Unterordner im ursprünglichen Schülerordner zurück (Original bleibt erhalten). Der Text nach `_k-` selbst hat **keinen** Einfluss darauf, wohin kopiert wird - er ist nur das Erkennungsmerkmal für "diese Datei ist korrigiert" und kann frei gewählt werden (z. B. das Kürzel des Ausbilders). Maßgeblich für den Zielordner ist stattdessen das Schüler-Kürzel, das bereits vorne im (unveränderten) Dateinamen steht (`pke` im Beispiel) - dieselben Initialen, die beim ursprünglichen Hochladen bereits die Zuordnung Kürzel → Schülerordner in `reviewMarker.kuerzelRoutesFile` angelegt haben. Kann DocFlowEngine dafür keinen Schülerordner ermitteln, legt es `<Dateiname>.KUERZEL-UNBEKANNT.txt` an, statt die Datei stillschweigend zu überspringen. Details und Designentscheidungen: [docs/Konzepte/ERWEITERUNGSKONZEPT.md](docs/Konzepte/ERWEITERUNGSKONZEPT.md).

### Alt-Bestand nachträglich ins Namensschema bringen

`scripts/Rename-ExistingAufgaben.ps1` ist ein **eigenständiges, manuell auszuführendes** Skript (kein
Teil des automatischen Laufs/der Aufgabenplanung) für bereits vorhandene Dateien, die nicht dem
Namensschema folgen (z. B. Alt-Bestand von vor der Einführung von DocFlowEngine). Es benennt jede
Datei so gut wie möglich in die Form `initialen_praefix_suffix_aufgabennummer` um - für Teile, die
sich nicht zuverlässig bestimmen lassen (Präfix/Suffix nur anhand der Whitelist in
`project-routes.txt`, Initialen/Aufgabennummer nur anhand der Namensstruktur), wird der Platzhalter
`PLATZHALTER` eingesetzt, statt zu raten.

```powershell
# Vorschau (Standard - es wird nichts verändert)
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Rename-ExistingAufgaben.ps1 -Path "C:\...\SchuelerMaterial\Max Mustermann"

# Tatsächliches Umbenennen
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Rename-ExistingAufgaben.ps1 -Path "C:\...\SchuelerMaterial\Max Mustermann" -Apply
```

`-Path` ist bewusst frei wählbar (ein einzelner Schülerordner, mehrere, oder der ganze
Austauschordner) - das Skript durchsucht ihn rekursiv. Ohne `-Apply` wird nur eine Tabelle
angezeigt (alter Name → neuer Name), ohne dass etwas verändert wird - wichtig, da ein
Massen-Umbenennen echter Dateien anhand einer Heuristik schwer rückgängig zu machen ist. Liegt eine
Datei unterhalb eines konfigurierten `sources[]`-Eintrags, registriert `-Apply` sie zusätzlich in
`.docflow-state.json` - **DocFlowEngine überspringt migrierte Dateien danach automatisch** beim
nächsten regulären Lauf, statt sie erneut zu erkennen und ggf. eine Namenskonvention-Hinweisdatei
dafür anzulegen. Bereits vom Skript erzeugte Hinweisdateien (`.NAMENSKONVENTION-FEHLER.txt`,
`.KUERZEL-UNBEKANNT.txt`) sowie Dateien im `Korrigiert`-Ordner werden von der Umbenennung
ausgenommen.

### Regelmäßige Automatisierung

**Windows: Geplante Aufgaben (keine Admin-Rechte nötig für User Tasks)**

Pro Rechner werden **zwei zeitlich versetzte Aufgaben** angelegt, keine einzelne: zuerst ein
OneDrive-Sync-Anstoß (`scripts/Invoke-OneDriveSync.ps1`), erst 10 Minuten später der eigentliche
DocFlowEngine-Lauf. Der Abstand gibt OneDrive Zeit, neu hochgeladene Schülerdateien tatsächlich
herunterzusynchronisieren, bevor DocFlowEngine den Ordner scannt - ohne diesen Puffer würde
DocFlowEngine ggf. gegen einen noch unvollständigen lokalen Ordnerstand laufen.

```powershell
$commonSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

# Aufgabe 1: OneDrive-Sync anstoßen, 08:00 Uhr
$syncAction = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\path\to\DocFlowEngine\scripts\Invoke-OneDriveSync.ps1"
$syncTrigger = New-ScheduledTaskTrigger -Daily -At 08:00
Register-ScheduledTask -Action $syncAction -Trigger $syncTrigger -Settings $commonSettings -Principal $principal -TaskName "DocFlowEngine-Sync" -Description "Stoesst OneDrive-Sync vor dem DocFlowEngine-Lauf an"

# Aufgabe 2: DocFlowEngine selbst, 10 Minuten spaeter
$runAction = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\path\to\DocFlowEngine\scripts\DocFlowEngine.ps1"
$runTrigger = New-ScheduledTaskTrigger -Daily -At 08:10
Register-ScheduledTask -Action $runAction -Trigger $runTrigger -Settings $commonSettings -Principal $principal -TaskName "DocFlowEngine-Run" -Description "Automated document processing"
```

Zwei Einstellungen sind hier bewusst explizit gesetzt, nicht nur der Standard:

- **`-RunOnlyIfNetworkAvailable`**: Beide Aufgaben starten nur, wenn eine Netzwerkverbindung besteht
  (relevant z. B. bei Laptops, die morgens erst noch ins WLAN kommen müssen) - ohne Netzwerk liefe
  DocFlowEngine sonst gegen einen (noch) nicht synchronisierten OneDrive-Ordner.
- **`-LogonType Interactive`** (über `New-ScheduledTaskPrincipal`): Die Aufgaben laufen nur, wenn der
  Benutzer angemeldet ist - nicht "unabhängig von der Anmeldung" (`-LogonType S4U`/`Password`). Das
  ist kein Stil-, sondern ein Notwendigkeits-Punkt: Der OneDrive-Client (und damit der lokal
  gespiegelte Ordner, den DocFlowEngine liest) läuft selbst nur innerhalb einer interaktiven
  Benutzersitzung. Eine Aufgabe im Hintergrund-Modus ohne Anmeldung liefe in einer Sitzung, in der
  OneDrive gar nicht aktiv ist - das betrifft beide Aufgaben, `Invoke-OneDriveSync.ps1` genauso wie
  `DocFlowEngine.ps1` selbst.

**`Invoke-OneDriveSync.ps1` ehrlich eingeordnet:** Es gibt keinen offiziellen "Sync jetzt"-Befehl von
Microsoft. Das Skript beendet den OneDrive-Prozess des Benutzers und startet ihn neu, was einen
frischen Dateicheck erzwingt - das ist ein **Anstoßen**, keine garantierte, blockierende
"warte bis fertig"-Operation. Genau deshalb der 10-Minuten-Puffer bis zum eigentlichen Lauf statt
eines Wartens auf ein (nicht existierendes) Abschluss-Signal. Ist `OneDrive.exe` nicht auffindbar
(z. B. Rechner ohne OneDrive), überspringt das Skript den Neustart mit einer Warnung, statt
abzubrechen.

**Mehrere Rechner: Zeiten gegeneinander staffeln**

Für den Multi-Machine-Betrieb (siehe [docs/Konzepte/MULTI-MACHINE-SETUP.md](docs/Konzepte/MULTI-MACHINE-SETUP.md))
zusätzlich die Uhrzeiten pro Rechner versetzen, damit nicht alle Rechner gleichzeitig auf die
geteilten Dateien zugreifen (die Lock-Datei fängt Kollisionen zwar ab, ein versetzter Zeitplan
vermeidet unnötig übersprungene Läufe aber von vornherein):

| Rechner | Sync-Aufgabe | DocFlowEngine-Aufgabe |
|---|---|---|
| Rechner A | 08:00 | 08:10 |
| Rechner B | 08:20 | 08:30 |
| Rechner C | 08:40 | 08:50 |

Der 10-Minuten-Abstand zwischen Sync- und Run-Aufgabe (siehe oben) bleibt pro Rechner gleich - nur
der Startzeitpunkt jedes Rechner-Paars wandert, analog zu `$syncTrigger`/`$runTrigger` oben mit
jeweils angepasster `-At`-Uhrzeit.

**macOS/Linux: Cron (ohne Admin-Rechte)**

`Invoke-OneDriveSync.ps1` ist Windows-spezifisch (OneDrive-Desktop-Client unter `$env:LOCALAPPDATA`) -
auf macOS/Linux entfällt der erste Schritt, hier reicht ein einzelner Cron-Eintrag:

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
| `Lauf abgebrochen: aktive Lock-Datei ... gefunden` | Ein anderer Rechner läuft gerade (oder ein vorheriger Lauf ist abgestürzt und die Lock-Datei ist noch "frisch", siehe `lockTimeoutMinutes`). Nach Ablauf des Timeouts übernimmt der nächste Lauf automatisch; die Lock-Datei kann bei Bedarf auch manuell gelöscht werden |
| Dateien werden auf mehreren Rechnern doppelt kopiert | Siehe [docs/Konzepte/MULTI-MACHINE-SETUP.md](docs/Konzepte/MULTI-MACHINE-SETUP.md) - `stateFile`/`projectRoutesFile`/`lockFile` müssen auf einen geteilten Ordner zeigen, nicht auf lokale Pfade |

## Dokumentation

Detail-Dokumentation liegt unter [`docs/`](docs/README.md), aufgeteilt nach Themen:

- [docs/Compatibility-und-Admin-Rechte.md](docs/Compatibility-und-Admin-Rechte.md) - Nachweis: reines PowerShell 5.1, keine Admin-Rechte nötig
- [docs/Configuration.md](docs/Configuration.md) - Alle Optionen von `config/docflow-config.psd1`
- [docs/Module-Reference.md](docs/Module-Reference.md) - Funktionsreferenz der Teilmodule
- [docs/Logging.md](docs/Logging.md) - Log-Level, Log-Format, Verhalten im DryRun
- [docs/Testing.md](docs/Testing.md) - Pester-Tests installieren und ausführen

Konzeptdokumente (Repo-Root):

- [docs/Konzepte/MULTI-MACHINE-SETUP.md](docs/Konzepte/MULTI-MACHINE-SETUP.md) - DocFlowEngine auf mehreren Rechnern betreiben (geteilter Ordner, Lock-Datei, deterministische Benennung)
- [docs/Konzepte/ERWEITERUNGSKONZEPT.md](docs/Konzepte/ERWEITERUNGSKONZEPT.md) - Konzept und Umsetzung der Pro-Datei-Namenskonvention-Hinweise, des "Korrigiert"-Rücklaufs, der Präfix/Suffix-Whitelist und der Modularisierung

## Sicherheit & Admin-Rechte

- **Keine Admin-Rechte erforderlich** für die Ausführung des Skripts (Details und Nachweis: [docs/Compatibility-und-Admin-Rechte.md](docs/Compatibility-und-Admin-Rechte.md))
- `-ExecutionPolicy Bypass` gilt nur für diesen Prozess, nicht systemweit
- Zugriffsrechte benötigt: Lesezugriff auf Quellordner, Schreibzugriff auf Zielordner
- Zustandsdatei (`stateFile`) wird am konfigurierten Pfad gespeichert (muss schreibbar sein) - im Multi-Machine-Betrieb üblicherweise im geteilten OneDrive/SharePoint-Ordner statt im lokalen Repo-Verzeichnis, siehe [docs/Konzepte/MULTI-MACHINE-SETUP.md](docs/Konzepte/MULTI-MACHINE-SETUP.md)
- Log-Datei wird im konfigurierten Pfad gespeichert (Verzeichnis muss existieren oder `createIfMissing` setzen)