# Konfiguration (`config/docflow-config.psd1`)

Die Konfiguration ist eine PowerShell-Data-Datei (`.psd1`), geladen über das eingebaute
`Import-PowerShellDataFile` (verfügbar seit PowerShell 5.0 - keine externen Module nötig). Defaults
für fehlende optionale Felder setzt `Load-Config` (`scripts/DocFlowEngine/Config.ps1`).

## `sources` (Pflicht)

Array von Quellordnern.

```powershell
sources = @(
    @{
        path             = 'C:/Users/p0*/OneDrive - D*/.../Austauschordner/'
        recursive        = $true
        includePatterns  = @('*.pdf', '*.docx')
        excludePatterns  = @('.*', 'Thumbs.db', '~$*', '*.NAMENSKONVENTION-FEHLER.txt', '*.KUERZEL-UNBEKANNT.txt')
    }
)
```

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `path` | string | ja | Ordnerpfad, darf `*`/`?`-Wildcards enthalten (z. B. für rechnerabhängige Benutzernamen). Wird über `Resolve-SourcePaths` (`Common.ps1`) zur Laufzeit aufgelöst; ein Wildcard-Pfad kann zu mehreren tatsächlichen Ordnern auflösen. |
| `recursive` | bool | ja | `$true` durchsucht Unterordner. |
| `includePatterns` | string[] | ja | Dateimuster (`-Filter`-Syntax von `Get-ChildItem`), z. B. `*.pdf`. |
| `excludePatterns` | string[] | nein | Namensmuster (`-like`), die trotz `includePatterns` ausgeschlossen werden. **Muss** die eigenen Hinweisdatei-Suffixe enthalten (`*.NAMENSKONVENTION-FEHLER.txt`, `*.KUERZEL-UNBEKANNT.txt`), sonst werden diese beim nächsten Lauf fälschlich als Quelldateien erkannt. |

Der `Korrigiert`-Unterordner (siehe `reviewMarker` unten) muss **nicht** separat in
`excludePatterns` eingetragen werden - er wird unabhängig davon per Ordnername erkannt und
übersprungen (`Test-DocFlowInsideNamedFolder`, `CopyForward.ps1`).

## `targets` (Pflicht)

Array von Standard-Zielordnern (für Dateien, die nicht über `aufgabenRoot` geroutet werden).

```powershell
targets = @(
    @{
        path               = 'C:/Users/p0*/OneDrive - D*/.../docs/archive'
        createIfMissing    = $true
        preserveSubfolders = $false
    }
)
```

| Feld | Typ | Beschreibung |
|---|---|---|
| `path` | string | Zielordner, ebenfalls wildcardfähig. |
| `createIfMissing` | bool | `$false` lässt `Invoke-DocFlowEngine` mit Fehler abbrechen, falls der Ordner fehlt, statt ihn anzulegen. |
| `preserveSubfolders` | bool | `$true` spiegelt die relative Unterordnerstruktur der Quelle im Ziel. |

## `aufgabenRoot` (optional)

```powershell
aufgabenRoot = 'C:/Users/p0*/OneDrive - D*/.../docs/Aufgaben'
```

Wurzelverzeichnis für Aufgaben-Abgaben. Dateien, deren Name dem Schema
`initialen[_v<version>]_praefix_suffix_aufgabennummer` entspricht **und** deren Präfix/Suffix in
`projectRoutesFile` als bekannt hinterlegt sind (siehe unten), werden nach
`<aufgabenRoot>/<Präfix>/<Suffix>/` kopiert statt in `targets`.

## `namingConventions` (Pflicht)

Array von Umbenennungsregeln, der Reihe nach geprüft - die erste passende Regel gewinnt.

```powershell
namingConventions = @(
    @{
        name        = 'Initials-Praefix-Suffix-Aufgabe'
        description = 'Format initialen[_v<version>]_praefix_suffix_aufgabennummer'
        match       = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
        rename      = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
    }
)
```

| Feld | Beschreibung |
|---|---|
| `match` | .NET-Regex mit benannten Gruppen (`(?<name>...)`), angewendet auf den Dateinamen ohne Endung. |
| `rename` | Template für den Zieldateinamen; `{gruppenname}` wird durch den jeweiligen Regex-Treffer ersetzt, zusätzlich stehen `{originalName}`, `{extension}`, `{date}`, `{timestamp}` zur Verfügung. |
| `description` | Nur für Menschen/Fehlermeldungen, keine Funktionslogik. |

Passt keine Regel, greift `defaultNameFormat` als Fallback (siehe unten).

## `namingConventionHint` (optional, Default siehe unten)

Steuert die Pro-Datei-Hinweisdatei, die entsteht, wenn eine Datei unterhalb `aufgabenRoot` nicht
geroutet werden kann (Schema passt nicht **oder** Präfix/Suffix unbekannt, siehe `projectRoutesFile`).

```powershell
namingConventionHint = @{
    enabled        = $true
    fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'
    message        = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema ... Praefix={praefix} Suffix={suffix}'
}
```

| Feld | Default (falls weggelassen) | Beschreibung |
|---|---|---|
| `enabled` | `$true` | Hinweisdatei-Erzeugung an/aus. |
| `fileNameSuffix` | `.NAMENSKONVENTION-FEHLER.txt` | Wird an den Original-Dateinamen angehängt: `<Dateiname><fileNameSuffix>`. |
| `message` | (deutscher Standardtext) | Platzhalter: `{fileName}`, `{originalName}`, `{extension}`, `{praefix}`, `{suffix}`. `{praefix}`/`{suffix}` sind leer, wenn das Namensschema gar nicht erst gematcht hat. |

Es entsteht **eine Datei pro betroffener Originaldatei** (nicht eine geteilte Datei pro Ordner) -
existiert die Hinweisdatei schon, wird sie nicht erneut geschrieben.

## `reviewMarker` (optional, Default: deaktiviert)

Steuert den "Korrigiert"-Rücklauf: Ein Ausbilder benennt eine geprüfte Datei unterhalb
`aufgabenRoot` um und hängt `_k-<beliebiger Text>` an; DocFlowEngine kopiert sie daraufhin in
`<Schülerordner>/<korrigiertFolderName>/` zurück.

```powershell
reviewMarker = @{
    enabled              = $true
    pattern              = '_k-[A-Za-z0-9]+$'
    korrigiertFolderName = 'Korrigiert'
    kuerzelRoutesFile    = 'C:/Users/p0*/OneDrive - D*/.../_DocFlowEngine-Shared/kuerzel-routes.txt'
}
```

| Feld | Default | Beschreibung |
|---|---|---|
| `enabled` | `$false` | Muss explizit gesetzt werden, um den Rücklauf zu aktivieren. |
| `pattern` | `_k-[A-Za-z0-9]+$` | Regex, geprüft gegen den Dateinamen ohne Endung. Erkennt nur, **dass** die Datei als Korrektur markiert ist - der getroffene Text selbst wird nirgends ausgewertet (siehe unten). |
| `korrigiertFolderName` | `Korrigiert` | Name des Zielunterordners im Schülerordner. |
| `kuerzelRoutesFile` | `./config/kuerzel-routes.txt` | Pfad zur Kürzel→Schülerordner-Registry. Wird **automatisch** befüllt (siehe unten). Format: eine Zeile pro Kürzel, `kuerzel=<absoluter Pfad zum Schülerordner>` (z. B. `pke=C:\Users\p0kretzer\OneDrive - D...\SchuelerMaterial\Max Mustermann`), `#` für Kommentare. |

**Der Text nach `_k-` hat keinen Einfluss auf das Zielverzeichnis** - er dient nur als
Erkennungsmerkmal dafür, dass die Datei fertig geprüft ist, und kann frei gewählt werden (z. B. das
Kürzel des Ausbilders statt des Schülers). Maßgeblich für den Zielordner ist stattdessen das
Schüler-Kürzel, das bereits vorne im (unveränderten) Dateinamen steht: DocFlowEngine entfernt den
`_k-...`-Marker sowie ein vorangestelltes `{date}_` und wendet auf den Rest dieselben
`namingConventions`-Regeln an wie beim Hochladen (`Get-FileInitialsFromName`, `Naming.ps1`), um die
`initials`-Gruppe (das Schüler-Kürzel) zu ermitteln. Dieses Kürzel wird gegen `kuerzelRoutesFile`
nachgeschlagen. Die Zuordnung Kürzel → Schülerordner entsteht automatisch beim normalen Hochladen:
Sobald `Copy-NewFiles` eine Aufgabendatei mit bekanntem Präfix/Suffix verarbeitet, registriert
`Register-Kuerzel` (`CopyBack.ps1`) einmalig den unmittelbaren Ordner dieser Datei unter dem
extrahierten Kürzel. Kein manueller Pflegeaufwand.

## `unknownKuerzelHint` (optional, Default siehe unten)

Hinweisdatei, falls beim Korrigiert-Rücklauf für das aus dem Dateinamen ermittelte Kürzel (noch)
kein Schülerordner bekannt ist.

```powershell
unknownKuerzelHint = @{
    enabled = $true
    message = 'Die Datei "{fileName}" ist als Korrektur markiert, aber für das im Dateinamen erkannte Kürzel "{kuerzel}" ist noch kein Schülerordner bekannt. ...'
}
```

Erzeugt `<Dateiname>.KUERZEL-UNBEKANNT.txt` neben der betroffenen Datei. Platzhalter: `{fileName}`,
`{kuerzel}` (das aus dem Dateinamen ermittelte Kürzel, leer, falls es sich gar nicht bestimmen ließ).

## `projectRoutesFile` / `projectRoutesSeedFile` (optional)

```powershell
projectRoutesFile     = 'C:/Users/p0*/OneDrive - D*/.../_DocFlowEngine-Shared/project-routes.txt'
projectRoutesSeedFile = './config/project-routes.txt'
```

`projectRoutesFile` ist die zur Laufzeit **tatsächlich genutzte** Whitelist bekannter Präfixe/Suffixe
(Format: `praefix=<Name>` / `suffix=<Name>`, eine Zeile pro Eintrag, `#` für Kommentare). Nur wenn
**sowohl** Präfix **als auch** Suffix einer Datei hier bereits gelistet sind, wird sie nach
`aufgabenRoot` geroutet (`Test-DocFlowPraefixSuffixKnown`, `Naming.ps1`). Ein unbekannter Wert wird
**nicht** automatisch aufgenommen, sondern wie eine falsche Namenskonvention behandelt (siehe
`namingConventionHint` oben).

`projectRoutesSeedFile` (Default `./config/project-routes.txt`) ist der versionierte Startbestand im
Repo. Neue Fächer/Themen werden von Hand **in dieser Seed-Datei** ergänzt und eingecheckt - bei
jedem Lauf gleicht `Sync-ProjectRoutesFromSeed` (`Naming.ps1`) sie gegen `projectRoutesFile` ab:
Existiert `projectRoutesFile` noch nicht, wird es 1:1 aus der Seed-Datei angelegt; existiert es
bereits, werden nur dort fehlende Zeilen aus der Seed-Datei ergänzt (rein additiv - Zeilen, die nur
in `projectRoutesFile` stehen, bleiben unangetastet). Ein manuelles Kopieren auf den geteilten
Ordner ist damit nicht mehr nötig. Zeigen beide Felder auf denselben Pfad (Einzelrechner-Betrieb
ohne geteilten Ordner), findet keine Synchronisierung statt.

**Ist `projectRoutesFile` gar nicht gesetzt**, entfällt die Whitelist-Prüfung komplett (und damit
auch die Seed-Synchronisierung): Jeder syntaktisch zum Schema passende Präfix/Suffix wird akzeptiert
(altes, offenes Verhalten).

## `defaultNameFormat` (optional, Default `{timestamp}_{originalName}`)

```powershell
defaultNameFormat = '{date}_{originalName}'
```

Fallback-Template, wenn keine `namingConventions`-Regel passt. `{date}_{originalName}` (statt dem
Default `{timestamp}_{originalName}`) ist für Multi-Machine-Betrieb empfohlen: `{timestamp}` erzeugt
bei jedem Lauf einen neuen, nicht wiedererkennbaren Namen und verhindert damit den
Ziel-Existenz-Check (siehe [MULTI-MACHINE-SETUP.md](Konzepte/MULTI-MACHINE-SETUP.md)).

## `stateFile` (optional, Default `./.docflow-state.json`)

Pfad zur JSON-Zustandsdatei (bereits verarbeitete Quelldateien + zurückkopierte Korrigiert-Dateien).
Im Multi-Machine-Betrieb auf einen geteilten Ordner zeigen lassen.

## `stateRetentionYears` (optional, Default `3`)

```powershell
stateRetentionYears = 3
```

Vor jedem `Save-State` entfernt `Remove-DocFlowExpiredState` (`State.ps1`) alle Einträge aus
`processed` und `reviewedFiles`, deren `processedAt`-Zeitstempel älter als `stateRetentionYears`
Jahre ist - damit `stateFile` bei Dauerbetrieb nicht unbegrenzt wächst. Einträge ohne auswertbaren
Zeitstempel bleiben unangetastet (konservativ: im Zweifel nichts löschen). Auf `0` oder `$null`
setzen, um das Aufräumen zu deaktivieren. Im `-DryRun` wird nur geloggt, was entfernt würde - der
State bleibt unverändert (wird ohnehin nicht gespeichert).

## `lockFile` / `lockTimeoutMinutes` (optional)

```powershell
lockFile           = 'C:/Users/p0*/OneDrive - D*/.../_DocFlowEngine-Shared/.docflow-lock'
lockTimeoutMinutes = 15
```

`lockFile` (Default `$null` = kein Locking) aktiviert den Lock-Mechanismus für den Multi-Machine-
Betrieb (`scripts/DocFlowEngine/Lock.ps1`). `lockTimeoutMinutes` (Default `15`) legt fest, ab wann
eine vorgefundene Lock-Datei als "abgestürzter Lauf" gilt und überschrieben wird.

## `log` (optional, Default `@{ level = 'Info'; file = './docflow.log' }`)

```powershell
log = @{
    level = 'Info'  # Trace | Debug | Info | Warning | Error
    file  = 'C:/Users/p0*/OneDrive - D*/.../_DocFlowEngine-Shared/docflow.log'
}
```

Details siehe [Logging.md](Logging.md).

## Vollständiges Beispiel

Siehe [config/docflow-config.psd1](../config/docflow-config.psd1) im Repo-Root für die tatsächlich
genutzte Konfiguration, sowie den kommentierten Beispiel-Workflow im
[Haupt-README](../README.md#beispiel-workflow).
