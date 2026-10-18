# DocFlowEngine

PowerShell-Modul, das Quellordner überwacht, neue Dokumente erkennt, sie nach definierten Regeln umbenennt und in eine Zielstruktur kopiert. Läuft mit Windows PowerShell 5.1 und PowerShell 7+, ohne Admin-Rechte und ohne externe Module.

## Quickstart

```powershell
git clone https://github.com/pkr-lab/DocFlowEngine.git
cd DocFlowEngine
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/DocFlowEngine.ps1 -DryRun
```

Pfade und Regeln stehen in `config/docflow-config.psd1`. Ohne `-DryRun` führt das Skript die Aktionen aus.

## Dokumentation

[Überblick](https://github.com/pkr-lab/pkr-lab-docs/blob/main/DocFlowEngine/index.md) · [Installation](https://github.com/pkr-lab/pkr-lab-docs/blob/main/DocFlowEngine/installation.md) · [Konfiguration](https://github.com/pkr-lab/pkr-lab-docs/blob/main/DocFlowEngine/konfiguration.md) · [Nutzung](https://github.com/pkr-lab/pkr-lab-docs/blob/main/DocFlowEngine/nutzung.md) · [Releases](https://github.com/pkr-lab/pkr-lab-docs/blob/main/DocFlowEngine/releases.md)

## Lizenz

Siehe [LICENSE](LICENSE).
