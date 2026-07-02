# Konfiguration von DocFlowEngine

## Struktur der `config/docflow-config.psd1`

Die Konfiguration ist eine PowerShell-Data-Datei (`.psd1`): eine Hashtable-Literal-Syntax
(`@{ key = 'value' }`), die mit dem eingebauten `Import-PowerShellDataFile` gelesen wird –
funktioniert identisch unter PowerShell 7+ und Windows PowerShell 5.1, ganz ohne Zusatzmodul.

- `sources` - Liste der Quellordner
  - `path` - Pfad zum Quellordner. Unterstützt Wildcards (z. B. `C:/Users/p0*/OneDrive - D*/SharePoint`), die mit `Resolve-Path` aufgelöst werden - jeder Treffer wird als eigener Quellordner mit den gleichen Einstellungen behandelt. Liefert ein Pfad keinen Treffer, wird er übersprungen und als Warning geloggt.
  - `recursive` - `$true` oder `$false` für Unterordner
  - `includePatterns` - Liste von Globs (z. B. `*.pdf`, `*.docx`)
  - `excludePatterns` - Optionale Liste von Globs, die auf den Dateinamen (nicht den vollen Pfad) angewendet werden, um Treffer aus `includePatterns` wieder auszuschließen (z. B. `Thumbs.db`, `desktop.ini`, `~$*` für temporäre Office-Dateien, `.*` für versteckte Dateien)
  - Dateien, die bereits unterhalb eines konfigurierten `targets`-Pfads oder von `aufgabenRoot` liegen, werden beim Scannen automatisch ausgeschlossen, damit DocFlowEngine seine eigenen Ausgabedateien nicht erneut einliest (relevant, wenn Quell- und Zielpfad denselben übergeordneten Ordner teilen).

- `targets` - Liste der Zielordner
  - `path` - Pfad zum Zielordner
  - `createIfMissing` - `$true` oder `$false`
  - `preserveSubfolders` - `$true` oder `$false`

- `namingConventions` - Regeln für die Umbenennung
  - `name` - Bezeichner der Regel
  - `description` - Optionale Beschreibung
  - `match` - Regex für den Dateinamen ohne Erweiterung
  - `rename` - Umbenennungsvorlage. Neben den benannten Regex-Gruppen stehen immer `{originalName}`, `{extension}`, `{timestamp}` (Zeitpunkt der Verarbeitung, `yyyyMMddHHmmss`) und `{date}` (Upload-Datum, `yyyyMMdd`) zur Verfügung.

- `aufgabenRoot` - Optionales Wurzelverzeichnis für die Aufgaben-Ablage
  - Liefert eine Namenskonvention beim Matching die Gruppen `praefix` und `suffix` (z. B. Schema `<initialen>_<praefix>_<suffix>_<aufgabennummer>`), wird die Datei nach `<aufgabenRoot>/<praefix>/<suffix>/` kopiert statt in die `targets`
  - Dateien ohne `praefix`/`suffix`-Treffer werden ganz normal über `targets` (bzw. `categoryRoutes`/`projectRoutesFile`) verarbeitet - `aufgabenRoot` schließt andere Dateien nicht aus

- `categoryRoutes` - Optionale Zuordnung von Kategorie zu Zielordner
  - `category` - Kategoriebezeichnung (z. B. "Java"), wird gegen den führenden Buchstaben-Teil der `project`-Gruppe geprüft (`StartsWith`, ohne Berücksichtigung von Groß-/Kleinschreibung)
  - `target` - Zielordner für diese Kategorie
  - Ist `categoryRoutes` konfiguriert, werden nur Dateien kopiert, deren Namenskonvention eine `project`-Gruppe liefert und zu einer Kategorie passt. Andere Dateien werden übersprungen und als Warning geloggt.

- `projectRoutesFile` - Optionaler Pfad zu einer Registry-Textdatei mit bekannten Präfixen und Suffixen
  - Format pro Zeile: `praefix=<Name>` oder `suffix=<Name>` (Beispiel: `praefix=Java`)
  - Zeilen, die mit `#` beginnen, und Leerzeilen werden ignoriert
  - Dient nur als Übersicht/Registry, nicht als Pfad-Zuordnung - der Zielpfad wird immer aus `aufgabenRoot/<praefix>/<suffix>` gebildet
  - DocFlowEngine ergänzt diese Datei automatisch um neu erkannte Präfixe/Suffixe (im `-DryRun`-Modus wird die Ergänzung nur geloggt, nicht geschrieben)
  - Beispieldatei: [`config/project-routes.txt`](../config/project-routes.txt)

- `defaultNameFormat` - Fallback-Name, falls keine Regel passt
- `stateFile` - Statusdatei zum Speichern bereits verarbeiteter Dateien
- `log` - Logging-Konfiguration
  - `level` - Log-Level
  - `file` - Logdatei-Pfad

## Beispiel

```powershell
@{
    sources = @(
        @{
            path            = './docs/incoming'
            recursive       = $true
            includePatterns = @('*.pdf', '*.docx')
        }
    )

    targets = @(
        @{
            path               = './docs/archive'
            createIfMissing    = $true
            preserveSubfolders = $false
        }
    )

    aufgabenRoot = './docs/Aufgaben'

    namingConventions = @(
        @{
            name        = 'Initials-Praefix-Suffix-Aufgabe'
            description = 'Format initialen_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc).'
            match       = '^(?<initials>[A-Za-z]+)_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename      = '{date}_{initials}_{praefix}_{suffix}_{aufgabennummer}'
        },
        @{
            name        = 'Date-prefix'
            description = 'Wenn der Dateiname mit Datum beginnt, wird es übernommen.'
            match       = '^(?<date>\d{4}-\d{2}-\d{2})[_\s-]+(?<name>.+)$'
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

## Hinweise zur `.psd1`-Syntax

- Jede Hashtable beginnt mit `@{` und endet mit `}`, Listen mit `@(...)`.
- Strings in einfachen Anführungszeichen (`'...'`) werden wörtlich übernommen - wichtig für Regex-Muster mit `$`, damit PowerShell sie nicht als Variablen interpretiert.
- `$true`/`$false` statt `true`/`false`.
- Kommentare beginnen mit `#`.
- `Import-PowerShellDataFile` lässt nur Daten zu (keine Funktionsaufrufe, keine Variablen) - das macht die Datei sicher einlesbar, auch ohne die Konfiguration zu vertrauen.
