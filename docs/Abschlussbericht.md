# Abschlussbericht: PowerShell-5.1-Kompatibilität & Codeprüfung

Stand: 2026-07-02. Dieser Bericht fasst das Gesamtkonzept von DocFlowEngine, die durchgeführte
Umstellung auf reine Windows-PowerShell-5.1-Kompatibilität (ohne Admin-Rechte, ohne Zusatzmodule)
sowie das Ergebnis der abschließenden Abhängigkeits- und Codeprüfung zusammen. Am Ende stehen die
Quellenangaben, die die zentralen Aussagen ("keine Admin-Rechte nötig", "läuft unter PowerShell 5.1")
technisch belegen.

## 1. Gesamtkonzept

DocFlowEngine ist ein PowerShell-Modul (`scripts/DocFlowEngine.psm1`) mit dünnem Wrapper-Skript
(`scripts/DocFlowEngine.ps1`), das konfigurierte Quellordner nach neuen Dateien durchsucht, sie anhand
regelbasierter Namenskonventionen umbenennt und in Zielordner kopiert – wahlweise mit Präfix/Suffix-
oder Kategorie-Routing (z. B. für Schüler-Aufgabenordner). Verarbeitete Dateien werden in einer
`.docflow-state.json` vermerkt, damit nichts doppelt kopiert wird. Die Konfiguration liegt als
PowerShell-Data-Datei (`config/docflow-config.psd1`) vor.

Zentrale Design-Vorgabe für dieses Projekt: Das Skript muss auf einem Windows-Rechner ohne Admin-Rechte
und ohne die Möglichkeit, PowerShell 7 zu installieren, laufen – also ausschließlich mit der auf jedem
Windows vorinstallierten **Windows PowerShell 5.1** und ohne zwingend zu installierende Zusatzmodule.

## 2. Ausgangslage

Der ursprüngliche Code nutzte mehrere Sprachelemente, die es in Windows PowerShell 5.1 nicht gibt:

| Element | Fund | Problem unter PS 5.1 |
|---|---|---|
| `??`-Operator | `DocFlowEngine.psm1:609` | Parser-Fehler ("Unerwartetes Token '??'"), da erst ab PowerShell 7.0 (siehe [Quelle 5/6](#quellen)) |
| `ConvertFrom-Json -AsHashtable` | `Load-State` | Parameter existiert erst ab PowerShell 6.0 (siehe [Quelle 4](#quellen)) |
| `[System.IO.Path]::GetRelativePath` | `Copy-NewFiles` | Methode existiert nur ab .NET Core 2.0 / .NET Standard 2.1, nicht im .NET Framework, auf dem PS 5.1 aufbaut (siehe [Quelle 7](#quellen)) |
| `ConvertFrom-Yaml` | `Load-Config` | Cmdlet ist erst ab PowerShell 7.4 nativ enthalten; für ältere Versionen wäre ein Zusatzmodul (`powershell-yaml`) nötig gewesen |

Das erklärte den vom Nutzer gemeldeten Parser-Fehler beim Aufruf mit `powershell.exe` (Windows
PowerShell 5.1).

## 3. Durchgeführte Änderungen

### 3.1 Sprachkompatibilität (PS 5.1 statt PS 7)

- `??`-Operator ersetzt durch explizite `if ($null -eq ...)`-Prüfung.
- `ConvertFrom-Json -AsHashtable` ersetzt durch eigene rekursive Funktion `ConvertTo-DocFlowHashtable`,
  die `PSCustomObject`-Bäume aus `ConvertFrom-Json` manuell in verschachtelte Hashtables überführt.
- `[System.IO.Path]::GetRelativePath` ersetzt durch `Get-DocFlowRelativePath`, die stattdessen
  `Uri.MakeRelativeUri` nutzt – diese .NET-Methode ist seit .NET Framework 2.0 durchgängig verfügbar
  (siehe [Quelle 8](#quellen)) und liefert damit auch unter PS 5.1 korrekte relative Pfade.

### 3.2 Konfigurationsformat: YAML → PowerShell-Data-Datei (`.psd1`)

Statt eines YAML-Parsers (der unter PS 5.1 immer ein externes Modul erfordert hätte) liegt die
Konfiguration jetzt als `config/docflow-config.psd1` vor und wird mit dem seit PowerShell 5.0
eingebauten Cmdlet `Import-PowerShellDataFile` gelesen (siehe [Quelle 3](#quellen)). Damit entfällt die
letzte verbliebene Abhängigkeit von einem Zusatzmodul vollständig – DocFlowEngine kommt jetzt ganz ohne
`Install-Module` aus.

`Import-PowerShellDataFile` liest die Datei zudem in einem eingeschränkten Sprachmodus (nur Literal-Werte,
keine Funktionsaufrufe) – das ist sicherer als `Invoke-Expression` auf beliebigen Skriptinhalt und war
auch ein Kriterium für diese Wahl.

### 3.3 Weitere Code-Bereinigung (diese Prüfung)

Bei der abschließenden Prüfung wurden zwei weitere Punkte gefunden und behoben:

1. **Widersprüchlicher Parameter in `Invoke-DocFlowEngine`:** `[Parameter(Mandatory)]` war zusammen mit
   einem Default-Wert für `-ConfigPath` gesetzt. Mandatory-Parameter ignorieren in PowerShell ihren
   Default-Wert und lösen bei fehlendem Argument eine interaktive Abfrage aus – das hätte z. B. bei
   direkten Funktionsaufrufen (Tests, interaktive Nutzung) zu einem hängenden Prompt geführt, obwohl ein
   sinnvoller Default existiert. `Mandatory` wurde entfernt, der Default bleibt bestehen.
2. **Nicht ausgewertetes `excludePatterns`:** Das Konfigurationsschema und die produktive
   `docflow-config.psd1` definieren pro Quelle `excludePatterns` (z. B. `Thumbs.db`, `desktop.ini`,
   `~$*`, `.*`), der Code in `Get-SourceFiles` hat dieses Feld aber nie ausgewertet. In der Praxis wären
   also z. B. temporäre Office-Sperrdateien (`~$Dokument.docx`) und `Thumbs.db` mitkopiert worden. Die
   Filterung wurde ergänzt: Nach dem Einlesen über `includePatterns` werden alle Treffer entfernt, deren
   Dateiname (`-like`-Vergleich, Wildcard-Syntax) zu einem `excludePatterns`-Eintrag passt.

Zusätzlich wurde `#Requires -Version 5.1` an den Anfang von `DocFlowEngine.ps1` und
`DocFlowEngine.psm1` gesetzt: Falls das Skript doch einmal auf einer älteren PowerShell-Version
(2.0–4.0) gestartet wird, bricht es sofort mit einer klaren Meldung ab, statt mit einem kryptischen
Parser-Fehler mitten im Code.

### 3.4 Nachtrag: Fehler aus dem ersten echten Testlauf (`Resolve-PathOrAbsolute`)

Der erste `-DryRun`-Lauf auf einem echten Windows-PowerShell-5.1-Rechner deckte einen weiteren,
statisch nicht erkennbaren Fehler auf: `targets[].path` und `aufgabenRoot` enthalten – genau wie
`sources[].path` – geräteabhängige Wildcards (`C:/Users/p0*/OneDrive - D*/...`), weil Benutzername und
OneDrive-Mandant je Gerät variieren. `Resolve-PathOrAbsolute` versuchte diese zunächst über
`Resolve-Path` aufzulösen; das schlägt aber fehl, solange der letzte Unterordner (z. B. `docs/archive`)
noch nicht existiert, weil er ja erst per `createIfMissing` angelegt werden soll. Als Fallback rief der
Code `[System.IO.Path]::GetFullPath(...)` auf – und diese Methode wirft unter Windows PowerShell 5.1
(.NET Framework) eine `ArgumentException` ("Illegales Zeichen im Pfad"), sobald der Pfad noch `*`/`?`
enthält (siehe [Quelle 11](#quellen)). Unter PowerShell 7 (.NET Core) ist dieselbe Methode toleranter,
weshalb der Fehler in der reinen Quelltextprüfung (Abschnitt 4) nicht auffiel.

`Resolve-PathOrAbsolute` wurde daher erweitert: Bei Wildcard-Pfaden, die als Ganzes nicht existieren,
werden vom Ende her Segmente abgeschnitten, bis ein existierendes (ggf. selbst wildcardhaltiges)
Elternverzeichnis über `Resolve-Path` gefunden wird; die abgeschnittenen Segmente werden anschließend
literal wieder angehängt. Details siehe [`docs/Module-Reference.md`](Module-Reference.md).

Die im selben Lauf aufgetretene Warnung `Quellverzeichnis '...FI*/Austauschordner/' existiert nicht oder
wurde nicht gefunden` ist davon unabhängig – `Resolve-SourcePaths` funktionierte korrekt und meldet
zurecht, dass für dieses Wildcard-Muster kein passender, tatsächlich existierender Ordner gefunden
wurde. Das ist kein Code-Bug, sondern deutet darauf hin, dass der konfigurierte Pfad/Musterteil
(`FI*/Austauschordner`) auf diesem Gerät so nicht existiert – bitte den tatsächlichen Ordnernamen unter
`C:\Users\p0*\OneDrive - ...\IT-Ausbildung Jahrgangsordner\` gegenprüfen und `includePatterns`/den Pfad
in `docflow-config.psd1` bei Bedarf anpassen.

## 4. Ergebnis der Abhängigkeits- und Codeprüfung

| Prüfpunkt | Ergebnis |
|---|---|
| Alle Cmdlets/Operatoren nur PS-5.1-Sprachumfang? | Ja – erneuter Volltext-Scan nach `??`, `-AsHashtable`, `GetRelativePath`, `-Parallel`, `$PSStyle` u. Ä. ergab keine Treffer mehr. |
| Externe Modul-Abhängigkeit? | Keine mehr. `Import-PowerShellDataFile`, `ConvertFrom-Json`, `ConvertTo-Json`, `Get-ChildItem`, `[Uri]`, `[System.Collections.Generic.HashSet]` u. a. sind seit PS 5.0/5.1 bzw. .NET Framework 2.0+ eingebaut. |
| Admin-Rechte für Ausführung nötig? | Nein (siehe [Quellen 1, 2, 9](#quellen)). |
| Admin-Rechte für optionale Modul-Installation (z. B. Pester für Tests) nötig? | Nein, sofern `-Scope CurrentUser` verwendet wird (siehe [Quelle 10](#quellen)). |
| Klammern-/Strukturbalance der `.psm1`- und `.psd1`-Dateien | Geprüft (Python-Skript, Klammern-/Parenthesen-Zählung) – ausgeglichen. |
| Tatsächlicher Parser-/Laufzeittest mit `pwsh`/`powershell.exe` | Erste Runde nur per Quelltextanalyse (kein PowerShell auf dem Entwicklungsrechner verfügbar). Ein späterer echter `-DryRun`-Lauf auf Windows PowerShell 5.1 deckte den in 3.4 beschriebenen, statisch nicht erkennbaren `Resolve-PathOrAbsolute`-Fehler auf – seitdem behoben, aber noch nicht erneut auf echter Hardware verifiziert. |

### Bekannte, bewusst nicht behobene Punkte

- `tests/DocFlowEngine.Tests.ps1` wird in README und `docs/Testing.md` erwähnt, existiert im Repository
  aber nicht. Das ist keine PS-5.1-Kompatibilitätsfrage, sondern eine Dokumentations-/Code-Lücke – falls
  gewünscht, kann ich das Testskript in einem separaten Schritt nachziehen.
- `ProjectRoutes`/`Get-ProjectRoutes`/`Resolve-ProjectTarget` sind implementiert und exportiert, werden
  aber in `Invoke-DocFlowEngine` nicht aufgerufen (bereits in `docs/Module-Reference.md` dokumentiert).
  Aktiv genutzt werden nur das Präfix/Suffix-Routing (`aufgabenRoot`) und `categoryRoutes`. Unverändert
  gelassen, da es sich um eine bestehende, bereits dokumentierte Designentscheidung handelt und nicht um
  einen PS-5.1-Bug.

## 5. Empfehlung für den nächsten Testlauf

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\DocFlowEngine.ps1 -DryRun
```

Der `Resolve-PathOrAbsolute`-Fix aus 3.4 wurde bisher nur per Quelltextanalyse geprüft, nicht auf einer
echten Windows-PowerShell-5.1-Installation. Bitte den Dry-Run erneut ausführen und prüfen, ob (a) für
`targets[].path` und `aufgabenRoot` jetzt keine `GetFullPath`-Exceptions mehr auftreten und (b) die
Warnung zum Quellordner (`FI*/Austauschordner`) verschwindet, sobald Pfad/Muster in
`docflow-config.psd1` an die tatsächliche Ordnerstruktur angepasst ist.

## Quellen

Belege für die beiden Kernaussagen dieses Projekts – "läuft unter Windows PowerShell 5.1" und "keine
Admin-Rechte nötig":

1. [about_Windows_PowerShell_5.1 – Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_5.1?view=powershell-5.1) – *"Windows PowerShell 5.1 is installed by default on Windows Server version 2016 and higher and Windows client version 10 and higher."* Belegt, dass PS 5.1 auf jedem unterstützten Windows bereits vorhanden ist (keine Installation, keine Admin-Rechte nötig). Dieselbe Seite bestätigt außerdem, dass Pester bereits in Version 3.4.0 mitgeliefert wird.
2. [What is Windows PowerShell? – Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/what-is-windows-powershell?view=powershell-7.6) – bestätigt, dass Windows PowerShell mit Windows ausgeliefert wird und Version 5.1 die aktuelle/letzte Version ist.
3. [Import-PowerShellDataFile (Microsoft.PowerShell.Utility) – Microsoft Learn, PS-5.1-Referenz](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-powershelldatafile?view=powershell-5.1) – eigene Dokumentationsseite für PowerShell 5.1 belegt, dass das Cmdlet dort nativ vorhanden ist (kein Zusatzmodul für das neue `.psd1`-Konfigurationsformat nötig).
4. [ConvertFrom-Json (Microsoft.PowerShell.Utility) – Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.6) – dokumentiert, dass der Parameter `-AsHashtable` erst mit PowerShell 6.0 eingeführt wurde und daher unter Windows PowerShell 5.1 nicht existiert (Begründung für die eigene `ConvertTo-DocFlowHashtable`-Funktion).
5. [about_Operators – Microsoft Learn, PS-7.4-Referenz](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_operators?view=powershell-7.4) – enthält die Abschnitte "Null-coalescing operator `??`", "Null-coalescing assignment operator `??=`", "Ternary operator" und "Null-conditional operators `?.` und `?[]`".
6. [about_Operators – Microsoft Learn, PS-5.1-Referenz](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_operators?view=powershell-5.1) – dieselbe Referenzseite für Windows PowerShell 5.1 enthält keinen dieser Abschnitte; Direktvergleich beider Versionen belegt, dass `??`, `??=`, der Ternary-Operator sowie `?.`/`?[]` unter 5.1 nicht existieren.
7. [Path.GetRelativePath(String, String) – Microsoft Learn (.NET-API-Referenz)](https://learn.microsoft.com/en-us/dotnet/api/system.io.path.getrelativepath?view=net-10.0) – die "Applies to"-Liste der unterstützten Ziel-Frameworks führt nur `netcore-2.0+`, `netstandard-2.1` und `net-5.0+` auf, **kein** `.NET Framework` (auf dem Windows PowerShell 5.1 basiert) – daher war die Methode im Originalcode ein Laufzeitrisiko unter PS 5.1.
8. [Uri.MakeRelativeUri(Uri) – Microsoft Learn (.NET-API-Referenz)](https://learn.microsoft.com/en-us/dotnet/api/system.uri.makerelativeuri?view=net-10.0) – die "Applies to"-Liste führt durchgängig `netframework-2.0` bis `netframework-4.8.1` auf; das ist die Grundlage für den PS-5.1-kompatiblen Ersatz `Get-DocFlowRelativePath`.
9. [about_Execution_Policies – Microsoft Learn, PS-5.1-Referenz](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1) – beschreibt den `Process`-Scope von `-ExecutionPolicy Bypass`: *"If you set the execution policy for the **Process** scope, it's not saved in the registry."* Admin-Rechte ("Run as administrator") werden laut Dokumentation nur benötigt, um die Policy dauerhaft im `LocalMachine`-Scope zu ändern – nicht für den in `DocFlowEngine.ps1`/README verwendeten `-ExecutionPolicy Bypass`-Aufruf pro Prozess.
10. [Install-Module (PowerShellGet) – Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershellget-2.x) – belegt, dass `-Scope CurrentUser` Module ins Benutzerprofil installiert und keine Elevation erfordert (relevant nur noch für die optionale Pester-Installation für Tests, nicht mehr für den produktiven Betrieb von DocFlowEngine selbst).
11. [Path.GetFullPath Method – Microsoft Learn (.NET-API-Referenz)](https://learn.microsoft.com/en-us/dotnet/api/system.io.path.getfullpath?view=net-8.0) – dokumentiert die `ArgumentException`, wenn der Pfad "one or more of the invalid characters defined in `GetInvalidPathChars()`" enthält; empirisch bestätigt durch den tatsächlichen Fehler ("Illegales Zeichen im Pfad") beim ersten `-DryRun`-Lauf auf Windows PowerShell 5.1, sobald der Pfad noch ein `*` enthielt – unter PowerShell 7/.NET Core trat dasselbe nicht auf. Grundlage für den in Abschnitt 3.4 beschriebenen Fix.
