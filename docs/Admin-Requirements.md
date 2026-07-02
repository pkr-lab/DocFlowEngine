# Admin-Anforderungen und Sicherheit

## Allgemein: Keine Admin-Rechte erforderlich

DocFlowEngine kann **vollständig ohne Admin-Rechte** ausgeführt werden. Alle Operationen laufen im User-Kontext ab.

## Schritt-für-Schritt: Was wird benötigt?

### 1. PowerShell 7+ Installation (optional)

DocFlowEngine läuft auch mit der auf jedem Windows bereits vorinstallierten **Windows PowerShell 5.1**
(`powershell.exe`) – es ist keine Installation und keine Admin-Berechtigung nötig. PowerShell 7 ist nur
empfohlen, aber nicht zwingend erforderlich. Es gibt keinen funktionalen Unterschied zwischen beiden:
Die Konfiguration liegt als PowerShell-Data-Datei (`.psd1`) vor und wird über das seit PowerShell 5.0
eingebaute `Import-PowerShellDataFile` gelesen – ganz ohne Zusatzmodul.

**Methode: Paketmanager (KEINE Admin-Rechte nötig für User-Installation)**

```bash
# macOS: Homebrew
brew install powershell

# Linux (Ubuntu): Snap
sudo snap install powershell --classic

# Windows: Chocolatey
choco install powershell-core

# Oder manuell vom GitHub-Release
# https://github.com/PowerShell/PowerShell/releases
```

**Status nach Installation:** ✓ Keine Admin-Rechte erforderlich

### 2. Modul-Abhängigkeiten

Keine. Das Konfigurationsformat (`.psd1`, gelesen über `Import-PowerShellDataFile`) und alle sonstigen
verwendeten Cmdlets sind sowohl in Windows PowerShell 5.1 als auch in PowerShell 7+ enthalten. Es muss
kein `Install-Module` ausgeführt werden, um DocFlowEngine selbst auszuführen.

#### Pester (für Tests, optional)

```powershell
# Nur für Tests notwendig (keine Admin nötig)
Install-Module -Name Pester -Scope CurrentUser -Force
```

**Status**: ✓ Keine Admin-Rechte erforderlich

### 3. Datei-Operationen

DocFlowEngine benötigt während der Ausführung:

| Operation                   | Anforderung                                | Admin nötig? |
|-----------------------------|--------------------------------------------|--------------|
| Lesezugriff auf Quellordner | Leseberechtigung auf Source-Verzeichnis    | Nein         |
| Schreiben in Zielordner     | Schreibberechtigung auf Target-Verzeichnis | Nein         |
| State-Datei erstellen       | Schreiben im aktuellen Arbeitsverzeichnis  | Nein         |
| Log-Datei schreiben         | Schreiben im Log-Verzeichnis               | Nein         |

**Beispiel: Typische Berechtigungen**
```bash
# Alle Operationen möglich ohne sudo
cd ~/Documents/DocFlowEngine
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1
```

### 4. Geplante Aufgaben (Automatisierung)

#### Windows: Task Scheduler

**User Task (KEINE Admin-Rechte nötig):**
```powershell
# Erstelle einen Task für den aktuellen User
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\path\to\DocFlowEngine\scripts\DocFlowEngine.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 08:00
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DocFlowEngine-User" -Description "Document Processing" -Settings $settings
```

**Status**: ✓ Keine Admin-Rechte erforderlich (wird als User Task registriert)

#### macOS/Linux: Cron

```bash
# Crontab ohne sudo bearbeiten (nur User-Cron)
crontab -e

# Beispiel:
0 8 * * * /usr/local/bin/pwsh -NoProfile -ExecutionPolicy Bypass -File ~/DocFlowEngine/scripts/DocFlowEngine.ps1
```

**Status**: ✓ Keine Admin-Rechte erforderlich

### 5. ExecutionPolicy

```powershell
# Diese Befehle erfordern KEINE Admin-Rechte:
pwsh -ExecutionPolicy Bypass -File .\scripts\DocFlowEngine.ps1
pwsh -ExecutionPolicy RemoteSigned -File .\scripts\DocFlowEngine.ps1
```

Die `-ExecutionPolicy` setzt die Policy nur für den aktuellen Prozess.

**Status**: ✓ Keine Admin-Rechte erforderlich

## Sicherheits-Überblick

| Aspekt                | Status                  | Anmerkung                            |
|-----------------------|-------------------------|--------------------------------------|
| Prozess-Ausführung    | ✓ User-Level            | Läuft im User-Kontext                |
| Dateisystem-Zugriff   | ✓ User-Rechte           | Benötigt nur Standard-Berechtigungen |
| Netzwerk              | ✓ Keine Anforderung     | Keine Netzwerk-Operationen           |
| Registry/System       | ✓ Keine Änderungen      | Keine systemweiten Änderungen        |
| Modul-Installation    | ✓ Current-User Scope    | `-Scope CurrentUser` nutzen          |

## Wenn du doch Admin-Rechte benötigst

Diese Szenarien **könnten** Admin-Rechte erfordern:

- Zielordner ist `C:\Windows`, `C:\Program Files`, etc. (Windows)
- Zielordner ist systemweit geschützt (`/usr/bin`, `/etc`, etc. auf Linux/macOS)
- Quelle ist ein netzwerkgebundenes Laufwerk ohne User-Zugriff
- Logging-Pfad ist systemweit geschützt

**Lösung:** Pfade auf User-Ordner setzen (z. B. `~/Documents`, `~/Downloads`, etc.)

## Beispiel-Konfiguration für maximale Kompatibilität

```powershell
@{
    sources = @(
        @{
            path            = '~/Documents/incoming'    # Benutzer-Verzeichnis
            recursive       = $true
            includePatterns = @('*.pdf')
        }
    )

    targets = @(
        @{
            path               = '~/Documents/archive'  # Benutzer-Verzeichnis
            createIfMissing    = $true
            preserveSubfolders = $false
        }
    )

    stateFile = '~/.docflow-state.json'  # Im Home-Verzeichnis
    log = @{
        level = 'Info'
        file  = '~/.docflow/logs/docflow.log'
    }
}
```

**Status**: ✓ Vollständig ausführbar ohne Admin-Rechte
