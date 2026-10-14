# Modul- und Funktionsreferenz

`scripts/DocFlowEngine.psm1` ist das Root-Modul: Es lädt per Dot-Sourcing alle Teilmodule aus
`scripts/DocFlowEngine/` (in dieser Reihenfolge: `Common.ps1`, `Config.ps1`, `State.ps1`,
`Lock.ps1`, `Naming.ps1`, `CopyForward.ps1`, `CopyBack.ps1`) und stellt `Invoke-DocFlowEngine` als
öffentlichen Einstiegspunkt bereit. `scripts/DocFlowEngine.ps1` ist der dünne CLI-Wrapper
(`-ConfigPath`, `-DryRun`), den `README.md` in den Ausführungsbeispielen verwendet.

Alle unten aufgeführten Funktionen sind über `Export-ModuleMember` öffentlich und in
`tests/DocFlowEngine.Tests.ps1` mindestens einmal direkt getestet.

## `DocFlowEngine.psm1` (Root)

| Funktion | Zweck |
|---|---|
| `Invoke-DocFlowEngine -ConfigPath <string> [-DryRun]` | Hauptablauf: Config laden, Lock erwerben, State laden, `Copy-NewFiles` + `Copy-ReviewedFiles` ausführen, State speichern, Lock freigeben. Einziger Ort, der die Teilmodule orchestriert. |

## `Common.ps1` - Logging, Pfade, generische Hilfsfunktionen

| Funktion | Zweck |
|---|---|
| `Write-Log -Level <Trace\|Debug\|Info\|Warning\|Error> -Message <string>` | Schreibt nach `Write-Host` und (falls konfiguriert) in die Log-Datei, gefiltert nach `log.level`. Siehe [Logging.md](Logging.md). |
| `Expand-Template -Template <string> -Context <hashtable>` | Ersetzt `{key}`-Platzhalter im Template durch Werte aus `Context`. |
| `Resolve-PathOrAbsolute -PathValue <string>` | Löst einen (ggf. wildcardhaltigen) Pfad zu einem absoluten Pfad auf, auch wenn er noch nicht existiert (schneidet Segmente vom Ende ab, bis ein existierender - ggf. ebenfalls wildcardhaltiger - Elternordner gefunden wird). |
| `Resolve-SourcePaths -PathValue <string>` | Löst einen Quellpfad zu allen tatsächlich existierenden, passenden Ordnern auf (`Resolve-Path`, kann bei Wildcards mehrere Treffer liefern). |
| `Test-PathExcluded -FullName <string> -ExcludePaths <array>` | Prüft, ob ein Pfad unterhalb eines der übergebenen Ausschlussordner liegt (Präfixvergleich). |
| `ConvertTo-DocFlowHashtable -InputObject <object>` | Wandelt rekursiv `PSCustomObject` (aus `ConvertFrom-Json`) in verschachtelte `Hashtable`s um - Ersatz für `ConvertFrom-Json -AsHashtable`, das erst ab PowerShell 6 existiert. |
| `Get-DocFlowRelativePath -BasePath <string> -FullPath <string>` | Berechnet den relativen Pfad rein per String-Verarbeitung (bewusst **kein** `[Uri]::MakeRelativeUri` - das erkennt POSIX-Pfade ohne `file://`-Schema nicht zuverlässig als absolut). Grundlage für den rechnerunabhängigen Dedup-Key in `Copy-NewFiles`. |
| `Copy-DocFlowFileWithRetry -Source <string> -Destination <string> [-RetryCount <int> = 2] [-RetryDelaySeconds <int> = 5]` | Kopiert mit bis zu `RetryCount` Wiederholungen und prüft nach jedem Versuch, ob die Zieldatei existiert und gleich groß ist. Gibt `$true`/`$false` zurück; loggt fehlgeschlagene Einzelversuche als `Warning`, das endgültige Scheitern als `Error`. |
| `Test-DocFlowFileReady -File <FileInfo> [-MinAgeMinutes <double>]` | `$false`, wenn die Datei jünger als `MinAgeMinutes` ist oder sich nicht exklusiv öffnen lässt (wird noch geschrieben/synchronisiert). |
| `Write-DocFlowHintFile -Path <string> -Content <string> -LogMessage <string>` | Schreibt eine Hinweisdatei, falls sie noch nicht existiert. Fehler beim Schreiben werden als `Error` geloggt statt den Lauf abzubrechen. |
| `Remove-DocFlowHintFile -Path <string> -Reason <string>` | Löscht eine Hinweisdatei (falls vorhanden) und loggt den Grund. Im DryRun nur Ankündigung. |
| `Remove-DocFlowOrphanedHintFiles -Directory <string> -HintSuffixes <string[]> [-Recurse <bool>]` | Löscht Hinweisdateien mit einer der Endungen, deren zugehörige Datei nicht mehr existiert. |

## `Config.ps1` - Konfiguration laden

| Funktion | Zweck |
|---|---|
| `Load-Config -Path <string>` | Lädt die `.psd1`-Konfiguration, validiert Pflichtfelder (`sources`, `namingConventions`, sowie `aufgabenRoot` oder `targets`), setzt Defaults für alle optionalen Felder und ersetzt zum Schluss die `{name}`-Verweise auf den `paths`-Block. Details siehe [Configuration.md](Configuration.md). |
| `Resolve-DocFlowPathVariables -Paths <hashtable>` | Löst die Einträge des `paths`-Blocks auf, inklusive Verweisen untereinander. Wirft bei unbekannten Namen und zirkulären Verweisen. |
| `Expand-DocFlowPathValue -Value <string> -PathVariables <hashtable> [-FieldName <string>]` | Ersetzt alle `{name}`-Verweise in einem einzelnen Pfadwert. `FieldName` erscheint in der Fehlermeldung, wenn ein Name fehlt. |
| `Expand-DocFlowConfigPaths -Config <hashtable>` | Wendet `Expand-DocFlowPathValue` auf alle Pfadfelder der Konfiguration an (Liste siehe [Configuration.md](Configuration.md#paths-optional-empfohlen---pfade-nur-ganz-oben-anpassen)). |

## `State.ps1` - Zustandsdatei

| Funktion | Zweck |
|---|---|
| `Load-State -StatePath <string>` | Lädt `.docflow-state.json`; liefert `@{ processed = @{}; reviewedFiles = @{} }`, falls die Datei fehlt oder nicht lesbar ist. |
| `Save-State -StatePath <string> -State <hashtable>` | Schreibt den State als JSON zurück, legt das Zielverzeichnis bei Bedarf an. |
| `Remove-DocFlowExpiredState -State <hashtable> -RetentionYears <int>` | Entfernt aus `processed` und `reviewedFiles` alle Einträge, deren `processedAt` älter als `RetentionYears` ist (Einträge ohne auswertbaren Zeitstempel bleiben erhalten). Gibt die Anzahl entfernter Einträge zurück. Wird in `Invoke-DocFlowEngine` vor `Save-State` aufgerufen (siehe [Configuration.md](Configuration.md), `stateRetentionYears`). |

## `Lock.ps1` - Multi-Machine-Lock

| Funktion | Zweck |
|---|---|
| `Test-DocFlowLockFresh -LockPath <string> -TimeoutMinutes <int>` | Prüft, ob eine vorhandene Lock-Datei jünger als `TimeoutMinutes` ist. |
| `Lock-DocFlowRun -LockPath <string> [-TimeoutMinutes <int> = 15]` | Versucht die Lock-Datei zu erwerben (Inhalt: `Hostname\|PID\|Zeitstempel`, ermittelt über `[System.Environment]::MachineName` - plattformunabhängig, PS-5.1-kompatibel). Gibt `$false` zurück, wenn eine frische Lock-Datei existiert. |
| `Unlock-DocFlowRun -LockPath <string>` | Entfernt die Lock-Datei. |

## `Naming.ps1` - Namenskonvention, Umbenennung, Whitelist

| Funktion | Zweck |
|---|---|
| `Get-TargetFileName -File <FileInfo> -Rules <array> -DefaultFormat <string>` | Ermittelt den Zieldateinamen anhand der ersten passenden `namingConventions`-Regel (per `[regex]::Match`, nicht `-match`/`$Matches` - damit liefert eine nicht getroffene optionale Gruppe wie `versiontag` garantiert einen leeren String statt eines fehlenden Platzhalters). Fällt sonst auf `DefaultFormat` zurück. |
| `Get-FileCategory` / `Resolve-CategoryTarget` | Legacy-Routing über führende Buchstaben + `categoryRoutes`; in der aktuellen Konfiguration ungenutzt. |
| `Get-FileProject` / `Get-ProjectRoutes` / `Resolve-ProjectTarget` | Legacy-Routing über eine `project`-Regexgruppe; in der aktuellen Konfiguration ungenutzt (nicht zu verwechseln mit der Präfix/Suffix-Whitelist in `project-routes.txt`, die trotz des Dateinamens ein eigenständiger Mechanismus ist). |
| `Get-FilePraefixSuffix -File <FileInfo> -Rules <array>` | Extrahiert `praefix`/`suffix` aus dem ersten Regel-Treffer mit beiden benannten Gruppen. |
| `Get-FileInitialsFromName -Name <string> -Rules <array>` | Extrahiert die `initials`-Gruppe (Schüler-Kürzel) aus einem Dateinamen (ohne Endung) anhand des ersten Regel-Treffers mit dieser Gruppe (per `[regex]::Match`, nicht `-match`/`$Matches`, analog zu `Get-TargetFileName`). Kernfunktion, von `Get-FileInitials` (Vorwärtslauf) und `Copy-ReviewedFiles` (Rücklauf, auf den vom `_k-...`-Marker befreiten Namen angewendet) gemeinsam genutzt. |
| `Get-FileInitials -File <FileInfo> -Rules <array>` | Dünner Wrapper um `Get-FileInitialsFromName` für den `FileInfo`-Fall. |
| `Test-DocFlowPraefixSuffixKnown -Registry <hashtable> -Praefix <string> -Suffix <string>` | Prüft, ob die **Kombination** in `Registry.Paare` steht. Fehlt `Paare` (selbst gebaute Registry), werden Präfix und Suffix wie früher einzeln geprüft. |
| `Get-DocFlowRegistryLines -Path <string>` | Liest eine Whitelist-Datei zeilenweise (getrimmt) und trennt dabei versehentlich zusammengeklebte Einträge wie `suffix=Registrysuffix=Arrays` wieder in einzelne Zeilen auf. Gemeinsame Lesebasis von `Get-PraefixSuffixRegistry` und `Sync-ProjectRoutesFromSeed`. Nicht exportiert. |
| `ConvertTo-DocFlowRegistryStructure -Lines <string[]>` / `ConvertFrom-DocFlowRegistryStructure -Structure <object>` | Wandelt Whitelist-Zeilen in eine nach Präfix gruppierte Struktur (`Groups`, `Orphans`, `Invalid`) und zurück in Zeilen. Basis für Laden und Abgleich. Nicht exportiert. |
| `Get-PraefixSuffixRegistry -Path <string>` | Lädt `project-routes.txt`: `Paare` (Präfix → `HashSet` erlaubter Suffixe) sowie zur Abwärtskompatibilität `Praefixe` und `Suffixe` (alle case-insensitive). Protokolliert Pfad und Anzahl der Kombinationen (`Info`), die vollständige Liste (`Debug`) sowie ungültige Zeilen und Suffixe vor dem ersten Präfix (`Warning`). |
| `Sync-ProjectRoutesFromSeed -SeedPath <string> -TargetPath <string>` | Legt `TargetPath` aus der Seed-Datei an, falls er fehlt. Sonst werden beide nach Präfix gruppiert zusammengeführt (fehlende Kombinationen aus der Seed-Datei unter den passenden Präfix, eigene Kombinationen bleiben) und die Datei nur bei einer Änderung neu geschrieben (UTF-8). No-op, falls beide Pfade identisch sind oder die Seed-Datei fehlt. |
| `Write-NamingConventionHint -File <FileInfo> -HintConfig <hashtable> [-PraefixSuffix <PSCustomObject>]` | Erzeugt die individuelle Hinweisdatei `<Dateiname><fileNameSuffix>` neben der betroffenen Datei (keine Wirkung, falls die Datei schon existiert). `-PraefixSuffix` optional, damit die Meldung `{praefix}`/`{suffix}` referenzieren kann. |
| `Get-DocFlowSubmissionParts -Name <string> -Rules <array>` | Zerlegt einen Dateinamen (ohne Endung) in `Initials`, `Version` (ohne `_v` = 1), `Praefix`, `Suffix`, `Aufgabennummer`. |
| `Find-DocFlowExistingSubmission -File <FileInfo> -TargetDirectory <string>` | Sucht im Zielordner eine Datei `<Datum>_<gleicher Dateiname>`. |
| `Get-DocFlowSuggestedVersionName -File <FileInfo> -Rules <array> [-TargetDirectory <string>]` | Schlägt den Dateinamen mit der nächsten freien Versionsnummer vor (höchste Version derselben Aufgabe im Schüler- und Zielordner + 1). |
| `Write-DocFlowDuplicateHint -File <FileInfo> -HintConfig <hashtable> [-SuggestedName <string>]` | Schreibt den `.BEREITS-ABGEGEBEN.txt`-Hinweis (`duplicateHint`). |
| `Get-DocFlowMigratedFileName -Name <string> -Rules <array> [-Registry <hashtable>] [-Placeholder <string> = 'PLATZHALTER']` | Best-effort-Ableitung eines regelkonformen Namens aus einem beliebigen Alt-Dateinamen: unverändert, falls `Name` bereits einer `Rules`-Regel entspricht; sonst Token-Suche nach genau einem bekannten Präfix/Suffix aus `Registry` (`Get-PraefixSuffixRegistry`), führende 2-5 Buchstaben als Initialen, letztes verbleibendes Token als Aufgabennummer - für jeden nicht bestimmbaren Teil `Placeholder`. Kernlogik von `scripts/Rename-ExistingAufgaben.ps1` (siehe unten). |

## `CopyForward.ps1` - Quell-Scan und Vorwärtskopie

| Funktion | Zweck |
|---|---|
| `Get-SourceFiles -Source <hashtable> -ResolvedPath <string>` | Scannt einen aufgelösten Quellordner nach `includePatterns`, wendet `excludePatterns` an. |
| `Ensure-TargetDirectories -Targets <array>` | Legt fehlende Zielordner an (sofern `createIfMissing` nicht `$false` ist) und normalisiert `target.path` auf den aufgelösten Pfad. |
| `Test-DocFlowInsideNamedFolder -DirectoryName <string> -FolderName <string>` | Prüft, ob ein Pfad-Segment exakt `FolderName` entspricht (z. B. `Korrigiert`) - robuster als ein `-like`-Muster auf den Dateinamen, da er auf ganzen Pfadsegmenten statt nur dem Dateinamen prüft. |
| `Get-DocFlowFileFingerprint -File <FileInfo>` | Liefert `Length` und `LastWriteUtcSeconds` einer Datei für den Zustandseintrag. |
| `Test-DocFlowSameFileVersion -Entry <hashtable> -File <FileInfo> [-ToleranceSeconds <int> = 2]` | Vergleicht einen Zustandseintrag mit der aktuellen Datei (gleiche Größe, Änderungszeit innerhalb der Toleranz). |
| `Test-DocFlowHintFileName -Name <string> [-HintSuffixes <string[]>]` | `$true`, wenn der Name auf eine der Hinweis-Endungen endet. |
| `Copy-NewFiles -Sources ... -Targets ... -State ... -Rules ... -DefaultNameFormat ... [-AufgabenRoot ...] [-PraefixSuffixRegistry ...] [-RegistryFilePath ...] [-KuerzelRoutes ...] [-KuerzelRoutesFilePath ...] [-KorrigiertFolderName ...] [-NamingConventionHint ...] [-DuplicateHint ...] [-MinFileAgeMinutes ...] [-RetryCount ...] [-RetryDelaySeconds ...] [-ExcludePaths ...]` | Kernfunktion des Vorwärtslaufs. Reihenfolge je Datei: Ausschlüsse → Zustand (unverändert: überspringen; ohne Größe/Zeit: nachtragen; überschrieben: `duplicateHint`) → `Test-DocFlowFileReady` → Routing nach `aufgabenRoot`/Präfix-Suffix-Paar/Legacy-Routing/`targets` → gleichnamige Abgabe im Zielordner (identisch: übernehmen, sonst `duplicateHint`) → `Copy-DocFlowFileWithRetry` → Zustandseintrag nur bei Erfolg, danach Hinweisdateien zur Datei entfernen. Vorab werden verwaiste Hinweisdateien im Quellordner entfernt. |

## `CopyBack.ps1` - "Korrigiert"-Rücklauf

| Funktion | Zweck |
|---|---|
| `Get-KuerzelRoutes -Path <string>` | Lädt `kuerzel-routes.txt` in eine `Hashtable` (Kürzel → Schülerordner-Pfad, case-insensitive). |
| `Register-Kuerzel -Routes <hashtable> [-RoutesFilePath <string>] -Kuerzel <string> -SourcePath <string>` | Trägt ein neues Kürzel einmalig ein (in-memory + Datei), no-op falls schon bekannt. Wird aus `Copy-NewFiles` heraus mit `$item.DirectoryName` aufgerufen (nicht der Quellwurzel - wichtig bei einem gemeinsamen, rekursiv gescannten Austauschordner mit Schüler-Unterordnern). |
| `Copy-ReviewedFiles -AufgabenRoot <string> -ReviewMarker <hashtable> -KuerzelRoutes <hashtable> -State <hashtable> -Rules <array> [-UnknownKuerzelHint <hashtable>] [-RetryCount <int>] [-RetryDelaySeconds <int>]` | Marker-Erkennung ohne Rücksicht auf Groß-/Kleinschreibung; Kopie über `Copy-DocFlowFileWithRetry`, Zustandseintrag nur bei Erfolg; entfernt danach einen vorhandenen `.KUERZEL-UNBEKANNT.txt`-Hinweis sowie vorab alle verwaisten. | Durchsucht `aufgabenRoot` rekursiv nach `_k-...`-markierten Dateien. Der Marker-Text selbst wird nirgends ausgewertet - stattdessen entfernt die Funktion den Marker sowie ein führendes `{date}_` und ermittelt über `Get-FileInitialsFromName -Rules $Rules` das Schüler-Kürzel aus dem verbleibenden (unveränderten) Dateinamen. Schlägt dieses Kürzel in `KuerzelRoutes` nach, kopiert nach `<Schülerordner>/<Korrigiert>/`. Überspringt bereits zurückkopierte Dateien (State) und Dateien, die bereits im `Korrigiert`-Ordner selbst liegen. |

## Aufrufreihenfolge in `Invoke-DocFlowEngine`

```
Load-Config
  → Lock-DocFlowRun (falls lockFile konfiguriert und nicht -DryRun)
    → Ensure-TargetDirectories
    → Load-State
    → Sync-ProjectRoutesFromSeed (falls projectRoutesFile + projectRoutesSeedFile konfiguriert)
    → Get-PraefixSuffixRegistry (falls projectRoutesFile konfiguriert)
    → Get-KuerzelRoutes (falls reviewMarker.kuerzelRoutesFile konfiguriert)
    → Copy-NewFiles           (Vorwärtslauf, inkl. Register-Kuerzel bei Bedarf)
    → Copy-ReviewedFiles      (Rücklauf, nur falls aufgabenRoot + reviewMarker.enabled)
    → Remove-DocFlowExpiredState (falls stateRetentionYears > 0)
    → Save-State              (nicht im DryRun)
  → Unlock-DocFlowRun (finally-Block, immer falls Lock erworben wurde)
```

## Eigenständige Skripte (kein Teil von `Invoke-DocFlowEngine`)

Diese beiden Skripte importieren zwar dasselbe Modul, laufen aber unabhängig vom regulären
`Invoke-DocFlowEngine`-Ablauf und werden nicht über die Aufgabenplanung mit ausgeführt (außer
explizit so eingerichtet, siehe README).

| Skript | Zweck |
|---|---|
| `scripts/Invoke-OneDriveSync.ps1` | Kein Modul-Import. Beendet den OneDrive-Prozess des Benutzers und startet ihn neu (`Stop-Process`/`Start-Process`), um einen frischen Sync-Check anzustoßen - kein offizieller, garantierter "Sync jetzt"-Befehl existiert. `-ExecutablePath` überschreibbar; ohne gefundene `OneDrive.exe` (z. B. `$env:LOCALAPPDATA` nicht gesetzt, wie auf macOS/Linux) bricht das Skript kontrolliert mit einer Warnung ab statt mit einem Fehler. |
| `scripts/Rename-ExistingAufgaben.ps1 -Path <string> [-ConfigPath <string>] [-Apply]` | Manuell auszuführendes Migrationsskript für Alt-Bestand. Nutzt `Load-Config`/`Get-PraefixSuffixRegistry`/`Get-DocFlowMigratedFileName`/`Lock-DocFlowRun`/`Load-State`/`Save-State`. Ohne `-Apply` reine Vorschau (keine Änderung). Mit `-Apply`: benennt Dateien um (Kollisionsschutz durch angehängten Zähler) und registriert sie - falls `-Path` unterhalb eines konfigurierten `sources[]`-Eintrags liegt - unter demselben Dedup-Key-Format wie `Copy-NewFiles` (`"$($source.path)\|<relativer Pfad>"`) in `.docflow-state.json`, damit `Invoke-DocFlowEngine` sie beim nächsten Lauf nicht erneut als neue Datei behandelt. |
