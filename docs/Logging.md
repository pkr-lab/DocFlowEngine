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
| `Zieldatei existiert bereits, überspringe Kopie: ...` | Ziel-Existenz-Check hat gegriffen (Multi-Machine-Absicherung, siehe [MULTI-MACHINE-SETUP.md](Konzepte/MULTI-MACHINE-SETUP.md)). |
| `Datei '...' entspricht nicht der erwarteten Namenskonvention. Hinweis-Datei erstellt: ...` | Naming-Hint wurde erzeugt (Schema nicht erfüllt oder Präfix/Suffix unbekannt). |
| `Whitelist geladen: '...' (6 Präfixe, 11 Kombinationen)` | Pfad und Umfang der tatsächlich genutzten Präfix/Suffix-Whitelist. Weichen die Zahlen von der Erwartung ab, wird eine andere Datei gelesen als gedacht, oder Zeilen sind fehlerhaft. Bei `log.level = 'Debug'` folgt die vollständige Liste der Einträge. |
| `Datei '...': Präfix '...' ist nicht in der Whitelist '...' eingetragen.` / `Datei '...': Suffix '...' ist für Präfix '...' nicht in der Whitelist '...' eingetragen.` | Dateiname passt zum Schema, aber der Präfix fehlt oder die Kombination ist nicht erlaubt. Die Datei wird nicht kopiert, der Schüler bekommt eine Hinweisdatei. |
| `Datei '...' passt nicht zum Schema ...` | Dateiname verletzt das Schema selbst (z. B. Leerzeichen, Bindestrich, Umlaut, fehlender Suffix). |
| `Ungültige Zeile in Whitelist '...' ignoriert` / `Unbekannter Schlüssel '...' in Whitelist '...' ignoriert` | Eine Zeile in `project-routes.txt` hat nicht die Form `praefix=<Name>` bzw. `suffix=<Name>` und wird nicht berücksichtigt. |
| `Kein Ziel für '...' ermittelbar (...). Datei wird übersprungen.` | Datei ist nicht über `aufgabenRoot` routbar, es sind keine `targets` konfiguriert und der Namenshinweis ist abgeschaltet. Die Datei wird nicht kopiert und beim nächsten Lauf erneut geprüft. |
| `Kopierversuch 1 von 3 fehlgeschlagen: ... Neuer Versuch in 5 Sekunden.` | Einzelner Kopierversuch gescheitert, es wird automatisch wiederholt (`copyRetry`). |
| `[ERROR] Kopieren nach 3 Versuchen fehlgeschlagen: ... Wird beim nächsten Lauf erneut versucht.` | Alle Versuche gescheitert. Die Datei steht nicht im Zustand und wird im nächsten Lauf neu versucht. |
| `Datei '...' wurde vor weniger als 2 Minuten geändert ...` / `Datei '...' ist gerade gesperrt ...` | Datei wird noch geschrieben/synchronisiert (`minFileAgeMinutes`); Verarbeitung im nächsten Lauf. |
| `Datei '...' wurde nach der Abgabe unter gleichem Namen überschrieben ...` | Schüler hat eine bereits kopierte Datei überschrieben; keine Kopie, Hinweis `.BEREITS-ABGEGEBEN.txt` (`duplicateHint`). |
| `Datei '...' wurde bereits abgegeben ('...'). Sie wird nicht erneut kopiert ...` | Im Zielordner liegt schon eine Abgabe mit diesem Namen; keine Kopie, Hinweis mit Vorschlag der nächsten Version. |
| `Datei '...' liegt bereits identisch in '...'. Wird als verarbeitet übernommen.` | Zieldatei existierte schon in gleicher Größe (z. B. nach abgebrochenem Lauf); kein Hinweis. |
| `Hinweis-Datei entfernt (...)` | Ein Hinweis traf nicht mehr zu (Datei umbenannt, gelöscht oder erfolgreich verarbeitet) und wurde gelöscht. |
| `Whitelist-Datei '...' neu geschrieben (ergänzt um: Java/ArrayList, ...)` | Abgleich mit dem Startbestand hat Kombinationen ergänzt bzw. die Datei nach Präfix gruppiert. |
| `Suffix '...' in Whitelist '...' steht vor dem ersten praefix= ...` | Ein Suffix ohne Präfix darüber wird ignoriert. |
| `Bereits in früheren Läufen verarbeitet und daher übersprungen: 3` | Anzahl der Dateien eines Quellordners, die laut Zustandsdatei schon verarbeitet wurden und deshalb nicht erneut kopiert werden. |
| `Neues Kürzel erkannt und in Kuerzel-Registry aufgenommen: '...' -> '...'` | Kürzel→Schülerordner-Zuordnung wurde erstmalig registriert. |
| `Kopiere korrigierte Datei zurück: ... -> .../Korrigiert/...` | "Korrigiert"-Rücklauf hat eine Datei zurückkopiert. |
| `Unbekanntes Kürzel '...' in '...' - kein Schülerordner bekannt, Rückkopie übersprungen.` | Rücklauf konnte das Kürzel nicht auflösen, `unknownKuerzelHint` greift. |
| `Lauf abgebrochen: aktive Lock-Datei '...' gefunden (...)` | Ein anderer Rechner/Lauf hält den Lock; dieser Lauf endet sofort ohne Verarbeitung. |

## Fehlerdiagnose

Siehe README-Abschnitt [Troubleshooting](../README.md#troubleshooting) für die häufigsten
Fehlerbilder und ihre Log-Signaturen.
