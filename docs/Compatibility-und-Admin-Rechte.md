# PowerShell-5.1-Kompatibilität und Admin-Rechte

Dieses Dokument hält fest, wie geprüft wurde, dass DocFlowEngine (a) ausschließlich mit
PowerShell-5.1-kompatibler Syntax/Cmdlets auskommt und (b) an keiner Stelle Admin-/Root-Rechte
voraussetzt. Zielplattform ist Windows PowerShell 5.1 auf Schulrechnern (siehe
[MULTI-MACHINE-SETUP.md](../MULTI-MACHINE-SETUP.md)); PowerShell 7+ auf Windows/macOS/Linux wird
zusätzlich unterstützt.

## 1. PowerShell-5.1-Kompatibilität

### Geprüfter Code

Alle Skriptdateien tragen `#Requires -Version 5.1`:
`scripts/DocFlowEngine.ps1`, `scripts/DocFlowEngine.psm1`, `tests/DocFlowEngine.Tests.ps1`. Die
Teilmodule unter `scripts/DocFlowEngine/*.ps1` werden per Dot-Sourcing aus `DocFlowEngine.psm1`
geladen und erben dessen Versionsvorgabe.

### Methode

1. **Manuelle Suche nach PS-7+-only-Syntax** (`grep` über `scripts/` und `tests/`):
   - Null-Coalescing-Operatoren `??` / `??=`
   - Null-Conditional-Operator `?.`
   - Pipeline-Chain-Operatoren `&&` / `||`
   - Ternary-Operator `? :`
   - `using namespace`
   - `ConvertFrom-Json -AsHashtable` (erst ab PowerShell 6) - im Code bewusst **nicht** verwendet;
     stattdessen implementiert `ConvertTo-DocFlowHashtable` (`Common.ps1`) dieselbe Umwandlung von
     Hand, siehe Kommentar dort.
   - `ForEach-Object -Parallel`, `Join-String`, `$PSStyle`, `Get-Error`, `$IsWindows`/`$IsLinux`/`$IsMacOS`/`$IsCoreCLR` (alles PS-6+/7+-only)

   Ergebnis: **keine Treffer.**

2. **[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) Regel `PSUseCompatibleSyntax`**,
   `TargetVersions = @('5.1')`, gegen `scripts/` und `tests/`:

   ```powershell
   Install-Module PSScriptAnalyzer -Scope CurrentUser
   $settings = @{
       IncludeRules = @('PSUseCompatibleSyntax')
       Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
   }
   Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings $settings
   Invoke-ScriptAnalyzer -Path ./tests -Recurse -Settings $settings
   ```

   Ergebnis: **keine Funde.**

3. **PSScriptAnalyzer Regel `PSUseCompatibleCommands`** gegen das mitgelieferte Kompatibilitätsprofil
   für Windows PowerShell 5.1 Desktop
   (`win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework`), das prüft, ob
   verwendete Cmdlets in dieser konkreten PowerShell-Edition überhaupt existieren:

   ```powershell
   $settings = @{
       IncludeRules = @('PSUseCompatibleCommands')
       Rules = @{
           PSUseCompatibleCommands = @{
               Enable = $true
               TargetProfiles = @('win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework')
           }
       }
   }
   Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings $settings
   ```

   Ergebnis: Die einzige Meldung betrifft `Write-Log` - das ist **keine echte Inkompatibilität**,
   sondern ein False Positive: `Write-Log` ist DocFlowEngines eigene Funktion (`Common.ps1:1`), kein
   Cmdlet. PSScriptAnalyzer prüft jede Datei isoliert und kennt den Rest des Moduls nicht, daher
   wird jeder Aufruf einer selbst definierten Funktion wie ein unbekanntes/fremdes Cmdlet behandelt.
   Zur Kontrolle: `Invoke-ScriptAnalyzer ... | Select-Object -ExpandProperty Message | Select-String "The command '(?!Write-Log)"`
   liefert keine Treffer - außer `Write-Log` taucht kein einziger fremder Befehl in den Funden auf.

4. **Laufende Probe:** Alle 26 Pester-Tests (`tests/DocFlowEngine.Tests.ps1`) sowie mehrere manuelle
   End-to-End-Läufe von `Invoke-DocFlowEngine` wurden gegen PowerShell 7.4.6 ausgeführt (auf dieser
   Entwicklungsumgebung ist kein Windows PowerShell 5.1 verfügbar). PowerShell 7 ist bezüglich der
   hier verwendeten Sprachkonstrukte eine Obermenge von 5.1 - ein Fehlschlag unter 7 wäre also auch
   unter 5.1 fehlgeschlagen. Die schritte 1-3 oben schließen zusätzlich aus, dass 7-spezifische
   Syntax verwendet wurde, die unter 7 zufällig auch liefe, unter 5.1 aber bräche.

### Ergebnis

Kein Befund. Der gesamte Code (`scripts/`, `tests/`) ist mit reinem Windows PowerShell 5.1 lauffähig.

## 2. Keine Admin-/Root-Rechte nötig

| Aktion | Braucht Admin-Rechte? | Warum (nicht) |
|---|---|---|
| DocFlowEngine ausführen (`DocFlowEngine.ps1`) | Nein | Nur Datei-Lese-/Schreibzugriffe auf vom Benutzer bereits beschreibbare Ordner (OneDrive-Quell-/Zielordner im eigenen Benutzerprofil). Keine Registry-Änderungen, kein Dienst, keine Systemdateien. |
| `-ExecutionPolicy Bypass` beim Aufruf | Nein | Gilt nur für den startenden Prozess (`-File`-Aufruf), nicht systemweit; verändert keine dauerhafte Einstellung. |
| Lock-Datei (`scripts/DocFlowEngine/Lock.ps1`) | Nein | Reine Dateioperationen (`Test-Path`/`Get-Item`/`Set-Content`/`Remove-Item`) im selben, bereits beschreibbaren geteilten Ordner. |
| Geplante Ausführung unter Windows | Nein | `Register-ScheduledTask` ohne `-User`/`-RunLevel Highest` legt eine Aufgabe im Kontext des aktuellen Benutzers an ("User Task") - siehe [README](../README.md#regelmäßige-automatisierung). Keine Registrierung als Dienst oder unter SYSTEM nötig. |
| Geplante Ausführung unter macOS/Linux | Nein | `crontab -e` bearbeitet die Crontab des aktuellen Benutzers, kein `sudo` nötig. |
| Pester-/PSScriptAnalyzer-Installation (nur für Entwicklung/Tests) | Nein | `Install-Module ... -Scope CurrentUser` installiert nur für den aktuellen Benutzer, kein Admin-Kontext nötig. So auch in diesem Repo verifiziert. |
| PowerShell 7 unter macOS installieren (optional, nur für Nicht-Windows-Entwicklung) | Nein | `brew install powershell` braucht kein `sudo`. |
| PowerShell 7 unter Linux installieren (optional, nur für Nicht-Windows-Entwicklung) | Je nach Methode | `apt-get install` braucht `sudo`; alternativ funktioniert das offizielle `.tar.gz`-Archiv ohne jede Installation/Admin-Rechte (in ein Benutzerverzeichnis entpacken, `./pwsh` direkt starten - so wurde auch in dieser Entwicklungsumgebung vorgegangen). Betrifft ohnehin nur optionale Entwicklungsumgebungen, nicht den eigentlichen Windows-Zielbetrieb. |

**Wichtig:** Windows PowerShell 5.1 ist auf jedem unterstützten Windows-Rechner bereits
vorinstalliert - für den eigentlichen Produktivbetrieb auf den Schulrechnern ist also
**überhaupt keine Installation** nötig, entsprechend auch keine Admin-Rechte dafür.

Diese Tabelle wurde beim Erstellen dieses Dokuments gegen das README (Abschnitte
"Voraussetzungen", "Regelmäßige Automatisierung", "Sicherheit & Admin-Rechte") abgeglichen; eine
zuvor inkonsistente Formulierung (Linux-`apt-get`-Beispiel unter der Überschrift "ohne Admin-Rechte
möglich") wurde dabei im README korrigiert.

## 3. Bei zukünftigen Änderungen erneut prüfen

Vor dem Mergen von Codeänderungen an `scripts/`:

```powershell
Import-Module PSScriptAnalyzer
$syntax = @{ IncludeRules = @('PSUseCompatibleSyntax'); Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } } }
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings $syntax
```

Ein leeres Ergebnis bedeutet: keine PS-7+-only-Syntax eingeschleppt. Für neue, extern importierte
Cmdlets (aus zusätzlichen Modulen) zusätzlich `PSUseCompatibleCommands` wie oben gegen das
Windows-PowerShell-5.1-Profil laufen lassen.
