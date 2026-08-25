# Logging

Implementiert in `Write-Log` (`scripts/DocFlowEngine/Common.ps1`).

## Log-Level

Fünf Stufen, aufsteigend nach Wichtigkeit:

```
Trace < Debug < Info < Warning < Error
```

Konfiguriert über `log.level` in `config/docflow-config.psd1` (siehe
[Configuration.md](Configuration.md#log-optional-default--level--info-file--docflowlog-)). Nur
Meldungen **ab** dem konfigurierten Level werden ausgegeben - bei `level = 'Warning'` erscheinen
also `Warning`- und `Error`-Meldungen, aber keine `Info`- oder `Debug`-Meldungen. Ein unbekannter
oder fehlender Wert fällt auf `Info` zurück.

## Ausgabeziele

Jede Meldung geht an zwei Stellen gleichzeitig (sofern das Level passt):

1. **Konsole** über `Write-Host` - sichtbar bei interaktiver Ausführung und im Task-Scheduler-/
   Cron-Log (sofern die Ausgabe umgeleitet wird, siehe README-Beispiel `>> cron.log 2>&1`).
2. **Log-Datei** (`log.file`, aufgelöst über `Resolve-PathOrAbsolute`) über `Add-Content` - nur
   falls ein Pfad konfiguriert ist. Das Verzeichnis wird bei Bedarf automatisch angelegt (außer im
   `-DryRun`, siehe unten).

## Format

```
[2026-06-25 10:30:15] [Info] Kopiere Datei: '...pke_Java_Arrays_abc.pdf' -> '...20260625_pke_Java_Arrays_abc.pdf'
```

`[yyyy-MM-dd HH:mm:ss] [LEVEL] Nachricht` - reiner Text, ein Eintrag pro Zeile, kein strukturiertes
Format (kein JSON/CSV). Für Auswertungen eignet sich `Select-String`/`grep` auf die Log-Datei.

## Verhalten im `-DryRun`

- Meldungen zu Aktionen, die im DryRun **nicht** wirklich ausgeführt werden (Kopieren, Anlegen von
  Ordnern/Hinweisdateien), sind mit `[DryRun]` markiert, z. B.
  `[Info] [DryRun] Datei würde kopiert: ...`.
- Das Log-Verzeichnis wird im DryRun **nicht** automatisch angelegt (`Invoke-DocFlowEngine`
  überspringt das `New-Item` für `logDir`, wenn `-DryRun` gesetzt ist) - passend dazu, dass ein
  DryRun keine Seiteneffekte haben soll. Ist das Verzeichnis bereits vorhanden, wird trotzdem
  hineingeschrieben.
- Der Lock-Mechanismus wird im DryRun komplett übersprungen (kein Lock-Erwerb, keine Lock-Datei).

## Typische Meldungen

| Beispiel | Bedeutung |
|---|---|
| `Gefundene Dateien in '...': 4` | Anzahl der in einem Quellordner gefundenen (nicht ausgeschlossenen) Dateien vor Dedup-Prüfung. |
| `Kopiere Datei: ... -> ...` | Erfolgreiche Kopie im Vorwärtslauf. |
| `Zieldatei existiert bereits, überspringe Kopie: ...` | Ziel-Existenz-Check hat gegriffen (Multi-Machine-Absicherung, siehe [MULTI-MACHINE-SETUP.md](../MULTI-MACHINE-SETUP.md)). |
| `Datei '...' entspricht nicht der erwarteten Namenskonvention. Hinweis-Datei erstellt: ...` | Naming-Hint wurde erzeugt (Schema nicht erfüllt oder Präfix/Suffix unbekannt). |
| `Neues Kürzel erkannt und in Kuerzel-Registry aufgenommen: '...' -> '...'` | Kürzel→Schülerordner-Zuordnung wurde erstmalig registriert. |
| `Kopiere korrigierte Datei zurück: ... -> .../Korrigiert/...` | "Korrigiert"-Rücklauf hat eine Datei zurückkopiert. |
| `Unbekanntes Kürzel '...' in '...' - kein Schülerordner bekannt, Rückkopie übersprungen.` | Rücklauf konnte das Kürzel nicht auflösen, `unknownKuerzelHint` greift. |
| `Lauf abgebrochen: aktive Lock-Datei '...' gefunden (...)` | Ein anderer Rechner/Lauf hält den Lock; dieser Lauf endet sofort ohne Verarbeitung. |

## Fehlerdiagnose

Siehe README-Abschnitt [Troubleshooting](../README.md#troubleshooting) für die häufigsten
Fehlerbilder und ihre Log-Signaturen.
