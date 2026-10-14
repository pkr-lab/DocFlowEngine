# Konfiguration (`config/docflow-config.psd1`)

Die Konfiguration ist eine PowerShell-Data-Datei (`.psd1`), geladen über das eingebaute
`Import-PowerShellDataFile` (verfügbar seit PowerShell 5.0 - keine externen Module nötig). Defaults
für fehlende optionale Felder setzt `Load-Config` (`scripts/DocFlowEngine/Config.ps1`).

## `paths` (optional, empfohlen) - Pfade nur ganz oben anpassen

Alle Pfade der Konfiguration werden **einmal** ganz oben im Block `paths` als Wert festgelegt. Die
übrigen Einträge verweisen nur noch per `{name}` darauf. Ändert sich ein Ordner (anderer Jahrgang,
anderer OneDrive-Name, anderer Ablageort), wird ausschließlich der Wert in `paths` angepasst.

```powershell
paths = @{
    jahrgang = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner'
    quelle   = '{jahrgang}/FI*/Austauschordner/'
    material = '{jahrgang}/SchuelerMaterial'
    shared   = '{material}/_DocFlowEngine-Shared'
}

sources      = @(@{ path = '{quelle}'; ... })
aufgabenRoot = '{material}/docs/Aufgaben'
stateFile    = '{shared}/.docflow-state.json'
```

| Regel | Beschreibung |
|---|---|
| Namen | Buchstaben, Ziffern und `_` (z. B. `shared`, `quelle_fi25`). Groß-/Kleinschreibung zählt beim Verweis nicht. |
| Verkettung | Ein Wert in `paths` darf auf andere Werte in `paths` verweisen (`shared = '{material}/...'`). Die Reihenfolge der Einträge spielt keine Rolle. |
| Ersetzte Felder | `sources[].path`, `targets[].path`, `aufgabenRoot`, `projectRoutesFile`, `projectRoutesSeedFile`, `stateFile`, `lockFile`, `log.file`, `reviewMarker.kuerzelRoutesFile`. |
| Nicht ersetzt | Alle anderen Felder, insbesondere `namingConventions[].rename` und die Hinweis-Texte. Dort bleiben Platzhalter wie `{date}`, `{name}` oder `{fileName}` unverändert, auch wenn es einen gleichnamigen Eintrag in `paths` gäbe. |
| Fehler | Ein Verweis auf einen nicht definierten Namen oder ein zirkulärer Verweis (`a = '{b}'`, `b = '{a}'`) bricht `Load-Config` mit einer Fehlermeldung ab, die den Namen nennt. |
| Wildcards | `*`/`?` in den Werten bleiben erhalten und werden wie bisher erst zur Laufzeit aufgelöst. |

Die Ersetzung geschieht in `Load-Config` (`Expand-DocFlowConfigPaths`, `Config.ps1`), also bevor
irgendein anderer Teil der Engine die Pfade sieht. Ohne `paths`-Block funktionieren ausgeschriebene
Pfade weiterhin unverändert.

**Hinweis zur Zustandsdatei:** Der Dedup-Schlüssel in `stateFile` enthält den (aufgelösten) Wert von
`sources[].path`. Ergibt der neue `paths`-Block exakt denselben Text wie der vorher ausgeschriebene
Pfad, bleibt der Zustand gültig. Ändert sich der aufgelöste Quellpfad, gelten alle Dateien darunter
als neu.

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

## `targets` (optional, in der mitgelieferten Konfiguration nicht gesetzt)

Array von Standard-Zielordnern für Dateien, die **nicht** über `aufgabenRoot` geroutet werden.
Die mitgelieferte Konfiguration verzichtet bewusst darauf, es wird also kein `archive`-Ordner mehr
angelegt. Ohne `targets` gilt:

- Eine Datei wird nur kopiert, wenn sie über `aufgabenRoot` geroutet werden kann.
- Alle anderen Dateien bekommen eine Hinweisdatei (`namingConventionHint`). Ist der Hinweis
  abgeschaltet, wird `Kein Ziel für '...' ermittelbar ... Datei wird übersprungen.` geloggt.
- Übersprungene Dateien werden **nicht** in die Zustandsdatei eingetragen. Nach einer Umbenennung
  durch den Schüler oder einer Ergänzung der Whitelist werden sie beim nächsten Lauf normal verarbeitet.
- `Load-Config` verlangt dann `aufgabenRoot`; fehlen beide, bricht der Start mit einer Fehlermeldung ab.

Soll doch wieder ein Sammelordner genutzt werden, sieht ein Eintrag so aus:

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
`<aufgabenRoot>/<Präfix>/<Suffix>/` kopiert (und nicht in `targets`, falls gesetzt).

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
| `match` | .NET-Regex mit benannten Gruppen (`(?<name>...)`), angewendet auf den Dateinamen ohne Endung. Groß-/Kleinschreibung wird überall ignoriert, `_V2_` gilt also genauso wie `_v2_`. |
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

## `duplicateHint` (optional, Default siehe unten)

```powershell
duplicateHint = @{
    enabled        = $true
    fileNameSuffix = '.BEREITS-ABGEGEBEN.txt'
    message        = 'Deine Datei "{fileName}" wurde bereits abgegeben. Falls es sich um eine neue Version handelt, benenne sie bitte mit Versionsangabe um, z. B. "{suggestedName}", und lade sie erneut hoch.'
}
```

Hinweis an den Schüler, wenn eine Abgabe **unter einem schon verwendeten Namen** erneut auftaucht.
Die Datei wird dann **nicht** kopiert. Erkannt werden zwei Fälle:

1. Eine bereits kopierte Datei wurde im Schülerordner unter gleichem Namen **überschrieben**
   (Größe oder Änderungszeit weichen vom gespeicherten Stand ab, siehe `stateFile`).
2. Im Zielordner `<aufgabenRoot>/<Präfix>/<Suffix>/` liegt bereits eine Abgabe mit genau diesem
   Namen (mit beliebigem Datum davor), z. B. weil die alte Datei gelöscht und neu hochgeladen wurde.
   Ist die vorhandene Datei gleich groß, gilt sie als dieselbe Abgabe (etwa nach einem
   abgebrochenen Lauf) und wird ohne Hinweis als verarbeitet übernommen.

Platzhalter: `{fileName}`, `{suggestedName}`. `{suggestedName}` ist der Dateiname mit der
**nächsten freien Versionsnummer**: Gibt es im Schülerordner oder im Zielordner schon `_v2_`, wird
`_v3_` vorgeschlagen. Benennt der Schüler die Datei um, wird der Hinweis beim nächsten Lauf
automatisch entfernt (siehe „Hinweisdateien aufräumen“ unten).

## `minFileAgeMinutes` (optional, Default `2`)

```powershell
minFileAgeMinutes = 2
```

Eine Datei wird erst verarbeitet, wenn sie seit mindestens so vielen Minuten nicht mehr geändert
wurde. Zusätzlich wird geprüft, ob sie sich exklusiv öffnen lässt. Ist sie noch zu frisch oder
gesperrt (OneDrive synchronisiert noch, Upload läuft noch), wird sie ohne Zustandseintrag und ohne
Hinweis übersprungen und im nächsten Lauf erneut geprüft. `0` schaltet die Wartezeit ab (die
Sperrprüfung bleibt).

## `copyRetry` (optional, Default `@{ count = 2; delaySeconds = 5 }`)

```powershell
copyRetry = @{
    count        = 2
    delaySeconds = 5
}
```

Schlägt das Kopieren fehl, wird es im selben Lauf noch `count`-mal wiederholt, jeweils nach
`delaySeconds` Sekunden Pause. Nach jedem Versuch wird geprüft, ob die Zieldatei existiert und
genauso groß ist wie die Quelle. Scheitern alle Versuche, wird ein `Error` geloggt und die Datei
**nicht** als verarbeitet gespeichert; sie wird beim nächsten Lauf erneut versucht. Gilt für den
Vorwärtslauf und für den „Korrigiert“-Rücklauf.

## Hinweisdateien aufräumen (automatisch)

Bei jedem Lauf werden Hinweisdateien entfernt, die nicht mehr zutreffen:

- `*.NAMENSKONVENTION-FEHLER.txt` und `*.BEREITS-ABGEGEBEN.txt` im Schülerordner, wenn die Datei, auf
  die sie sich beziehen, nicht mehr existiert (umbenannt oder gelöscht), oder sobald diese Datei
  erfolgreich kopiert wurde.
- `*.KUERZEL-UNBEKANNT.txt` unter `aufgabenRoot`, wenn die korrigierte Datei nicht mehr existiert
  oder sobald sie zurückkopiert werden konnte.

Gelöscht werden ausschließlich Dateien mit genau diesen Endungen; jede Löschung wird geloggt, im
`-DryRun` nur angekündigt. Die Endungen werden außerdem automatisch zu den `excludePatterns` jeder
Quelle hinzugefügt, damit Hinweise nie selbst als Abgabe gelten.

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
| `pattern` | `_k-[A-Za-z0-9]+$` | Regex, geprüft gegen den Dateinamen ohne Endung, ohne Rücksicht auf Groß-/Kleinschreibung (`_k-ahf` und `_K-AHF` funktionieren gleich). Erkennt nur, **dass** die Datei als Korrektur markiert ist - der getroffene Text selbst wird nirgends ausgewertet (siehe unten). |
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

`projectRoutesFile` ist die zur Laufzeit **tatsächlich genutzte** Whitelist erlaubter
Präfix/Suffix-**Kombinationen** (Format: `praefix=<Name>` / `suffix=<Name>`, eine Zeile pro Eintrag,
`#` für Kommentare). Ein `suffix=` gehört immer zum `praefix=` direkt darüber:

```
praefix=Java
suffix=Arrays
suffix=ArrayList
praefix=Zahlensysteme
suffix=Hexadezimal
```

Hier sind `Java_Arrays`, `Java_ArrayList` und `Zahlensysteme_Hexadezimal` erlaubt, `Java_Hexadezimal`
nicht. Derselbe Suffix darf unter mehreren Präfixen stehen (z. B. `Einfuehrung`). Ein `suffix=` vor
dem ersten `praefix=` wird mit einer Warnung ignoriert. Nur wenn die Kombination hier steht, wird
eine Datei nach `aufgabenRoot` geroutet (`Test-DocFlowPraefixSuffixKnown`, `Naming.ps1`). Ein unbekannter Wert wird
**nicht** automatisch aufgenommen, sondern wie eine falsche Namenskonvention behandelt (siehe
`namingConventionHint` oben).

`projectRoutesSeedFile` (Default `./config/project-routes.txt`) ist der versionierte Startbestand im
Repo. Neue Fächer/Themen werden von Hand **in dieser Seed-Datei** ergänzt und eingecheckt - bei
jedem Lauf gleicht `Sync-ProjectRoutesFromSeed` (`Naming.ps1`) sie gegen `projectRoutesFile` ab:
Existiert `projectRoutesFile` noch nicht, wird es 1:1 aus der Seed-Datei angelegt. Existiert es
bereits, werden beide Dateien **nach Präfix gruppiert** zusammengeführt: Fehlende Kombinationen aus
der Seed-Datei kommen unter den passenden Präfix, Kombinationen, die nur in `projectRoutesFile`
stehen, bleiben erhalten. Hat sich dabei etwas geändert, wird `projectRoutesFile` sortiert neu
geschrieben; Kommentare in dieser Datei gehen dann verloren (in der Seed-Datei bleiben sie). Ist
nichts zu ergänzen, bleibt die Datei unverändert.

**Umstellung von älteren Versionen:** Frühere Versionen haben fehlende Zeilen einfach unten an die
geteilte Datei angehängt. Dadurch kann ein Suffix dort unter dem falschen Präfix stehen. Alle Fächer
einmal sauber in die Seed-Datei eintragen und die geteilte `project-routes.txt` einmalig löschen;
sie wird beim nächsten Lauf aus der Seed-Datei neu angelegt. Ein manuelles Kopieren auf den geteilten
Ordner ist damit nicht mehr nötig. Zeigen beide Felder auf denselben Pfad (Einzelrechner-Betrieb
ohne geteilten Ordner), findet keine Synchronisierung statt.

Jeder Eintrag muss in einer eigenen Zeile stehen (`praefix=`/`suffix=`, Groß-/Kleinschreibung egal,
ohne Umlaut). Zeilen in anderer Form werden mit einer Warnung im Log ignoriert.

Bei jedem Lauf wird `Whitelist geladen: '<Pfad>' (<n> Präfixe, <m> Kombinationen)` geloggt. Werden nur
Dateien kopiert, deren Präfix/Suffix im Startbestand steht (z. B. nur `Zahlensysteme_Hexadezimal`),
ist das ein Hinweis darauf, dass die eigenen Einträge nicht in der Datei unter diesem Pfad stehen
oder nicht lesbar sind. Für jede abgelehnte Datei nennt das Log außerdem, ob Präfix, Suffix oder
das Schema selbst das Problem ist (siehe [Logging.md](Logging.md#typische-meldungen)).

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

Ein Eintrag unter `processed` sieht so aus:

```json
"<source.path>|ahf_java_arrays_1.pdf": {
    "source": "C:\\...\\AHf\\ahf_Java_Arrays_1.pdf",
    "targets": ["C:\\...\\Aufgaben\\Java\\Arrays\\20261014_ahf_Java_Arrays_1.pdf"],
    "processedAt": "2026-10-14T10:30:15.0000000+02:00",
    "length": 18234,
    "lastWriteUtcSeconds": 63896063415
}
```

`length` und `lastWriteUtcSeconds` (Änderungszeit in Sekunden, UTC) erkennen, ob eine bereits
verarbeitete Datei später unter gleichem Namen überschrieben wurde (siehe `duplicateHint`).
Abweichungen der Änderungszeit bis 2 Sekunden werden toleriert, weil OneDrive Zeitstempel je nach
Rechner leicht unterschiedlich runden kann. Einträge aus älteren Versionen ohne diese Felder werden
beim nächsten Lauf automatisch ergänzt, ohne dass die Datei erneut kopiert wird.

Eine Datei wird nur dann in `processed` eingetragen, wenn **alle** Kopien erfolgreich waren. Nach
einem Kopierfehler, einem Namensfehler, einer Doppelabgabe oder wenn die Datei noch geschrieben
wird, fehlt der Eintrag, und die Datei wird im nächsten Lauf erneut geprüft.

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
