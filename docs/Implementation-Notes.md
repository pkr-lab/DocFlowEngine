# Implementierungsnotizen

Der Code selbst enthält bewusst keine Kommentare. Diese Seite sammelt die Begründungen für
Implementierungsentscheidungen, die nicht allein aus dem Code ersichtlich sind - sortiert nach
Teilmodul unter `scripts/DocFlowEngine/`. Konzeptionelle Entscheidungen (das "Was" und "Warum" ganzer
Features) stehen in [Konzepte/ERWEITERUNGSKONZEPT.md](Konzepte/ERWEITERUNGSKONZEPT.md) und
[Konzepte/MULTI-MACHINE-SETUP.md](Konzepte/MULTI-MACHINE-SETUP.md); hier geht es um einzelne,
nicht-offensichtliche Code-Entscheidungen innerhalb dieser Features.

## `Naming.ps1`

**`Get-TargetFileName` / `Get-FileInitialsFromName` nutzen `[regex]::new(...).Match(...)` statt des
`-match`-Operators mit `$Matches`.** Ein .NET-`Match`-Objekt liefert für eine im Pattern vorhandene,
aber nicht getroffene optionale Gruppe (z. B. `versiontag` bei einer Datei ohne Versionsangabe)
garantiert `.Groups['versiontag'].Value -eq ''` und `.Groups['versiontag'].Success -eq $false` -
unabhängig davon, ob `$Matches` (das Ergebnis von `-match`) für diese Gruppe überhaupt einen
Schlüssel anlegt. Mit `-match`/`$Matches` bliebe ein Platzhalter wie `{versiontag}` im
Umbenennungs-Template unter Umständen unersetzt im Dateinamen stehen, und `Get-FileInitialsFromName`
könnte nicht zuverlässig zwischen "Regel hat keine `initials`-Gruppe" und "Gruppe vorhanden, aber
nicht getroffen" unterscheiden.

## `Common.ps1`

**`Resolve-PathOrAbsolute` schneidet bei Wildcard-Pfaden Segmente vom Ende ab.** Ein Pfad wie
`C:/Users/p0*/OneDrive - D*/.../Aufgaben` kann als Ganzes noch nicht existieren (z. B. weil
`aufgabenRoot` erst beim ersten Lauf angelegt wird), enthält aber Wildcards für geräteabhängige
Segmente (Benutzername, OneDrive-Mandant), die sich nicht einfach mit `[System.IO.Path]::GetFullPath`
auflösen lassen. Die Funktion schneidet deshalb iterativ das letzte Pfadsegment ab, bis
`Resolve-Path` ein tatsächlich existierendes (ggf. selbst noch wildcardhaltiges) Elternverzeichnis
auflösen kann, und hängt die zuvor abgeschnittenen Segmente danach wieder literal an das aufgelöste
Ergebnis an.

**`ConvertTo-DocFlowHashtable` erzeugt bewusst `@{}` statt `[ordered]@{}`.** Eine
`OrderedDictionary` (`[ordered]@{}`) hat keine `.ContainsKey()`-Methode, sondern nur `.Contains()`.
`Copy-NewFiles` ruft auf `$State.processed` aber gezielt `.ContainsKey()` auf. Eine normale
`Hashtable` verhält sich hier identisch zum Original-Verhalten von `ConvertFrom-Json -AsHashtable`
(das erst ab PowerShell 6 existiert und deshalb hier per Hand nachgebaut wird).

## `Lock.ps1`

**Der Lock-Mechanismus ist bewusst ohne `Mutex` umgesetzt, rein mit `Test-Path`/`Get-Content`/
`Set-Content`/`Remove-Item`.** Ein systemweiter `Mutex` müsste plattform- und ggf.
prozessmodellabhängig funktionieren; eine einfache Datei im ohnehin schon geteilten
OneDrive/SharePoint-Ordner ist mit reinen PowerShell-5.1-Bordmitteln umsetzbar und passt zum
"eventual consistency"-Modell des restlichen Multi-Machine-Betriebs (siehe
[Konzepte/MULTI-MACHINE-SETUP.md](Konzepte/MULTI-MACHINE-SETUP.md)).

**`Test-DocFlowLockFresh` liest die Lock-Datei über `Get-Item -Force`.** Dateien mit führendem Punkt
(wie `.docflow-lock`) gelten auf macOS/Linux im PowerShell-Dateisystemprovider standardmäßig als
versteckt und werden von `Get-Item` ohne `-Force` nicht gefunden - obwohl `Test-Path` sie durchaus
sieht. Ohne `-Force` würde die Altersprüfung der Lock-Datei auf diesen Plattformen fälschlich
fehlschlagen.

**Der Lock wird nur außerhalb von `-DryRun` erworben** (siehe `Invoke-DocFlowEngine` in
`scripts/DocFlowEngine.psm1`). Ein `-DryRun`-Lauf soll keinerlei Seiteneffekte haben, und das
Anlegen/Entfernen einer Lock-Datei wäre einer.

## `CopyForward.ps1`

**`Copy-NewFiles` überspringt Dateien innerhalb des `Korrigiert`-Unterordners der Quelle
(`Test-DocFlowInsideNamedFolder`).** Der `Korrigiert`-Ordner liegt innerhalb desselben
Schülerordners, der auch als `sources[]`-Eintrag gescannt wird (siehe
[Konzepte/ERWEITERUNGSKONZEPT.md](Konzepte/ERWEITERUNGSKONZEPT.md), Abschnitt 2b). Ohne diesen
Check würde eine von `Copy-ReviewedFiles` dorthin zurückkopierte Datei beim nächsten Lauf
fälschlich erneut als "neue" Quelldatei erkannt und in einer Endlosschleife weiterverarbeitet.

**Bereits vorhandene Zieldateien werden übersprungen statt mit `-Force` überschrieben.** Das ist
eine Defense-in-Depth-Absicherung für den Multi-Machine-Betrieb (verhindert Datenverlust, falls die
State-Datei zwischen zwei Rechnern noch nicht synchronisiert ist) - Details siehe
[Konzepte/MULTI-MACHINE-SETUP.md](Konzepte/MULTI-MACHINE-SETUP.md).
