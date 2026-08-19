# DocFlowEngine auf mehreren Rechnern betreiben

Dieses Dokument beschreibt, wie DocFlowEngine so eingerichtet werden kann, dass es
parallel bzw. abwechselnd auf mehreren Rechnern läuft, ohne dass Dateien doppelt
verarbeitet werden. Grundlage ist eine Analyse des bestehenden Codes
(`scripts/DocFlowEngine.psm1`) und der Konfiguration (`config/docflow-config.psd1`).

**Zielplattform: PowerShell 5.1.** Alle hier vorgeschlagenen Änderungen müssen mit
PowerShell-5.1-Bordmitteln umsetzbar sein (keine `pwsh`-only Cmdlets, kein
Null-Coalescing-Operator `??`, keine Ternary-Operatoren) – passend zur bestehenden
`#Requires -Version 5.1`-Vorgabe in `scripts/DocFlowEngine.psm1`.

## 1. Warum "mehrere Rechner" aktuell nicht funktioniert

Es gibt drei Probleme, die sich gegenseitig verschärfen.

### a) State/Log/Registry sind rechnerlokal, nicht geteilt

In `config/docflow-config.psd1` sind `stateFile`, `log.file` und
`projectRoutesFile` relative Pfade (`./.docflow-state.json`, `./docflow.log`,
`./config/project-routes.txt`) – also relativ zum lokalen Repo-Klon. Läuft der Task
auf Rechner A und Rechner B, hat jeder seine eigene `.docflow-state.json`. Rechner B
weiß nichts von dem, was A schon kopiert hat → dieselbe Datei wird zweimal
verarbeitet. Da der Fallback `defaultNameFormat = '{timestamp}_{originalName}'`
einen Zeitstempel einbaut, entstehen dabei **zwei unterschiedlich benannte Kopien**
im Zielordner statt einer.

### b) Der eigentliche Blocker: der Dedup-Key ist ein absoluter Pfad

In `Copy-NewFiles` (`scripts/DocFlowEngine.psm1`) wird als Key
`$item.FullName.ToLowerInvariant()` genutzt – der volle, lokal aufgelöste Pfad. Die
Quelle ist aber als Wildcard-Pfad konfiguriert:
`C:/Users/p0*/OneDrive - D*/...`. Das `p0*` steht für den Windows-Benutzernamen,
der sich pro Gerät/Account unterscheidet. Das heißt: **selbst wenn die
State-Datei perfekt geteilt wird**, hat dieselbe Datei auf Rechner A den Key
`c:\users\p0kretzer\onedrive - .../x.pdf` und auf Rechner B
`c:\users\p0mueller\onedrive - .../x.pdf` – zwei verschiedene Keys für dieselbe
Datei. Eine geteilte State-Datei würde also *nicht* verhindern, dass die Datei auf
beiden Rechnern erneut kopiert wird. **Dieser Punkt muss zuerst behoben werden**,
alles andere baut darauf auf.

### c) `project-routes.txt` liegt im Git-Repo, wird aber zur Laufzeit beschrieben

`Register-PraefixSuffix` hängt neu erkannte Präfixe/Suffixe an
`config/project-routes.txt` an. Läuft das auf zwei unabhängigen Git-Klonen, laufen
die Klone auseinander (Merge-Konflikte oder stille Divergenz, je nachdem ob
committed/gepusht wird).

## 2. Empfohlene Architektur

Code (versioniert, identisch pro Rechner) und Laufzeitdaten (müssen geteilt sein)
strikt trennen – und dafür den Sync-Layer nutzen, der ohnehin schon vorhanden ist:
OneDrive/SharePoint.

### Baustein 1 – Dedup-Key relativieren (Codefix, Pflicht)

`$sourceKey` in `Copy-NewFiles` nicht mehr aus `$item.FullName` bilden, sondern aus
dem Pfad relativ zur aufgelösten Quellwurzel – analog zu `Get-DocFlowRelativePath`,
das für `preserveSubfolders` bereits existiert. Damit ist der Key auf jedem Rechner
identisch, unabhängig vom lokalen Benutzernamen/OneDrive-Mountpunkt.

### Baustein 2 – Laufzeitdaten in den bereits geteilten Ordner verschieben

`stateFile`, `log.file` (zumindest aber `projectRoutesFile`) nicht mehr relativ zum
Repo, sondern als Pfad *innerhalb* der SharePoint/OneDrive-Struktur konfigurieren,
z. B. `.../SchuelerMaterial/_DocFlowEngine-Shared/.docflow-state.json`.
`Resolve-PathOrAbsolute` unterstützt Wildcard-Pfade bereits, das lässt sich direkt
wiederverwenden. So bekommt jeder Rechner über den normalen OneDrive-Sync
automatisch den aktuellen Stand – ohne zusätzliche Infrastruktur (kein
Netzlaufwerk, kein eigener Server nötig).

### Baustein 3 – Lock-Datei gegen Schreibkonflikte

OneDrive-Sync ist nicht transaktional/sofort. Laufen zwei Rechner gleichzeitig,
kann es zu "conflicted copy"-Dateien bei der State-Datei kommen. Vor
`Copy-NewFiles` eine Lock-Datei im selben Shared-Ordner anlegen (Inhalt: Hostname +
PID + Zeitstempel), am Ende wieder löschen. Ist die Lock-Datei vorhanden und frisch
(z. B. < 15 Min), bricht der zweite Rechner den Lauf ab statt zu schreiben. Das ist
mit reinen PS-5.1-Bordmitteln machbar (`Test-Path`, `Get-Content`, `Set-Content`,
`Remove-Item` – kein `Mutex`, kein `pwsh`-only Feature nötig).

### Baustein 4 – Zeitversetzte Scheduled Tasks

Zusätzlich zur Lock-Datei: Task Scheduler/Cron auf den Rechnern nicht auf dieselbe
Uhrzeit legen (z. B. Rechner A um 08:00, Rechner B um 08:10), damit der
OneDrive-Sync zwischen den Läufen realistisch Zeit hat durchzulaufen.

### Baustein 5 – Defense-in-Depth: Ziel-Existenz-Check

Zusätzlich zur State-Datei vor dem Kopieren prüfen, ob die Zieldatei (nach
Naming-Regel) bereits existiert, und in dem Fall überspringen statt mit `-Force` zu
überschreiben. Das fängt den Fall ab, dass der State noch nicht synchronisiert ist.
Voraussetzung: Naming-Regeln müssen deterministisch sein – der `{timestamp}`-
Fallback in `defaultNameFormat` verträgt sich damit nicht, weil er bei jedem Lauf
einen neuen Namen erzeugt. Für den Multi-Rechner-Betrieb empfiehlt sich stattdessen
`{date}_{originalName}` (ohne Uhrzeit).

### Baustein 6 – Code-Verteilung

`scripts/` und `config/docflow-config.psd1` bleiben in Git, jeder Rechner macht
`git pull` vor der Ausführung (oder der komplette Repo-Ordner wird zusätzlich über
OneDrive gespiegelt – dann aber `.git` und die Laufzeitdateien per `.gitignore`
ausschließen, das aktuell im Repo fehlt).

## 3. Reihenfolge der Umsetzung

1. Dedup-Key auf relativen Pfad umstellen (Baustein 1) – ohne das bringt der Rest
   nichts.
2. `stateFile`/`projectRoutesFile` in den Shared-Ordner verlegen (Baustein 2),
   `.gitignore` ergänzen.
3. Lock-Mechanismus einbauen (Baustein 3).
4. `defaultNameFormat` deterministisch machen + optionalen Ziel-Existenz-Check
   (Baustein 5).
5. Zeitversetzte Scheduled Tasks konfigurieren (Baustein 4).
