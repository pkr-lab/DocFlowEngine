# Tests

`tests/DocFlowEngine.Tests.ps1` enthält [Pester](https://pester.dev/)-Tests für alle Teilmodule.
Stand bei Erstellung dieses Dokuments: 26 Tests, alle grün.

## Voraussetzungen

Pester ist **kein** Bestandteil der eigentlichen DocFlowEngine-Laufzeit (siehe
[Voraussetzungen im Haupt-README](../README.md#voraussetzungen) - "keine externen Module nötig"
bezieht sich auf `Invoke-DocFlowEngine` selbst). Für die Tests wird Pester 5 oder neuer benötigt,
installierbar ohne Admin-Rechte:

```powershell
Install-Module -Name Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
```

`-Scope CurrentUser` installiert nur für den aktuellen Benutzer - kein Admin-/Root-Kontext nötig
(siehe [Compatibility-und-Admin-Rechte.md](Compatibility-und-Admin-Rechte.md)). `-SkipPublisherCheck`
ist nur relevant, falls bereits eine ältere, aus einer anderen Quelle signierte Pester-Version
vorhanden ist (z. B. die mit Windows ausgelieferte Pester 3.4.0).

## Ausführen

```powershell
Invoke-Pester -Path ./tests/DocFlowEngine.Tests.ps1
```

Ausführlichere Ausgabe:

```powershell
$config = New-PesterConfiguration
$config.Run.Path = './tests/DocFlowEngine.Tests.ps1'
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

## Was getestet wird

| Bereich | Beispiele |
|---|---|
| Namenskonvention | Optionale Regex-Gruppe (`versiontag`) wird korrekt durch leeren String ersetzt statt als `{versiontag}` stehen zu bleiben; Kürzel-Extraktion (`Get-FileInitials`). |
| Pro-Datei-Hinweis | Individuelle statt geteilter Hinweisdatei; keine erneute Erzeugung, falls schon vorhanden. |
| Präfix/Suffix-Whitelist | Bekannte Kombination wird geroutet; unbekannte Kombination erzeugt Hinweis statt Kopie **und** wird nicht automatisch in die Registry aufgenommen; ohne konfigurierte Registry gilt das alte, offene Verhalten. |
| "Korrigiert"-Rücklauf | Kürzel-Registry-Rundlauf (Schreiben/Lesen); Rückkopie inkl. Dedup über zwei Läufe; unbekanntes Kürzel → Hinweisdatei statt Kopie; bereits im `Korrigiert`-Ordner liegende Dateien werden ignoriert. |
| Multi-Machine-Fixes | Dedup-Key hängt vom konfigurierten (ggf. wildcardhaltigen) `source.path` ab, nicht vom lokal aufgelösten Rechnerpfad; Ziel-Existenz-Check verhindert blindes Überschreiben; Dateien im `Korrigiert`-Unterordner werden beim Quell-Scan übersprungen. |
| Lock-Mechanismus | Zweiter Lauf wird bei frischer Lock-Datei abgewiesen; abgelaufene Lock-Datei wird übernommen; `Unlock-DocFlowRun` entfernt die Datei zuverlässig. |
| Config-Defaults | `Load-Config` setzt sinnvolle Defaults für alle optionalen Felder, wenn sie in der `.psd1` fehlen. |
| `Get-DocFlowRelativePath` | Plattformunabhängige, reine String-basierte Berechnung (kein `[Uri]`-basierter Ansatz, der unter Linux/macOS ohne `file://`-Schema fehlschlägt). |

## Testaufbau

- Jeder Test arbeitet in Pesters `$TestDrive` (temporäres, automatisch aufgeräumtes Verzeichnis) -
  es werden keine Dateien im Projektverzeichnis selbst angelegt.
- Datei-/Ordnernamen enthalten durchgehend `New-Guid`, um Kollisionen zwischen Tests im selben
  `$TestDrive`-Lauf zu vermeiden (`$TestDrive` wird nicht zwischen einzelnen `It`-Blöcken geleert).
- Alle Kernfunktionen werden direkt aufgerufen (keine Mocks für `Copy-Item`/`Set-Content` etc.) -
  die Tests prüfen also echtes Dateisystemverhalten, nicht nur Funktionsaufrufe.

## Manuelle End-to-End-Prüfung

Zusätzlich zu den automatisierten Tests wurde der komplette Ablauf (`Invoke-DocFlowEngine` gegen
eine Test-Konfiguration mit echten Fixture-Ordnern) mehrfach manuell durchgespielt: Vorwärtslauf,
wiederholter Lauf (Idempotenz), Korrigiert-Rücklauf, unbekanntes Kürzel, aktiver Lock-Konflikt,
bekannte/unbekannte Präfix-Suffix-Kombinationen. Diese Fixtures sind bewusst nicht Teil des Repos
(reine Wegwerf-Verzeichnisse während der Entwicklung) - die dauerhafte Absicherung liegt in den
Pester-Tests oben.
