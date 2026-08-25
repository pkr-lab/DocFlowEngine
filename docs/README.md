# DocFlowEngine – Dokumentation

Diese Detail-Dokumentation ergänzt die Kurzanleitung im [Haupt-README](../README.md).
Sie ist nach Themen aufgeteilt:

- [Compatibility-und-Admin-Rechte.md](Compatibility-und-Admin-Rechte.md) - Nachweis: läuft alles mit reinem PowerShell 5.1 und ohne Admin-Rechte?
- [Configuration.md](Configuration.md) - Alle Optionen von `config/docflow-config.psd1` im Detail
- [Module-Reference.md](Module-Reference.md) - Funktionsreferenz der Teilmodule unter `scripts/DocFlowEngine/`
- [Logging.md](Logging.md) - Log-Level, Log-Format, Verhalten im DryRun
- [Testing.md](Testing.md) - Pester-Tests installieren und ausführen

Weiterführende Konzeptdokumente (bewusst im Repo-Root, nicht hier, da sie eigenständige
Entscheidungsdokumente sind):

- [../MULTI-MACHINE-SETUP.md](../MULTI-MACHINE-SETUP.md) - Betrieb auf mehreren Rechnern
- [../ERWEITERUNGSKONZEPT.md](../ERWEITERUNGSKONZEPT.md) - Herleitung der Pro-Datei-Hinweise, des "Korrigiert"-Rücklaufs, der Präfix/Suffix-Whitelist und der Modularisierung
