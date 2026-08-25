# Erweiterungskonzept: Multi-Machine-Setup, Namenskonvention & Korrigiert-Rücklauf, Sprachwahl

Dieses Dokument sammelt Lösungswege und Ideen für drei Fragestellungen rund um DocFlowEngine.

**Status: umgesetzt.** Alle unten beschriebenen Entscheidungen sind implementiert:
`scripts/DocFlowEngine.psm1` ist in Teilmodule unter `scripts/DocFlowEngine/` aufgeteilt
(Common, Config, State, Lock, Naming, CopyForward, CopyBack), `config/docflow-config.psd1`
ist entsprechend konfiguriert, und `tests/DocFlowEngine.Tests.ps1` deckt die neuen Funktionen
mit Pester-Tests ab. Abweichungen von der ursprünglichen Planung, die sich erst beim
Implementieren/Testen gezeigt haben, sind an den jeweiligen Stellen als **Korrektur beim
Implementieren** markiert.

Bezug: `scripts/DocFlowEngine.psm1`, `config/docflow-config.psd1`, `README.md`, `MULTI-MACHINE-SETUP.md` (bereits vorhandenes Konzept für Mehrmaschinenbetrieb).

---

## 1. Multi-Machine-Setup: OneDrive-Sync vs. Git-Sync

`MULTI-MACHINE-SETUP.md` beschreibt bereits drei Root Causes, warum DocFlowEngine auf mehreren Maschinen aktuell nicht sauber funktioniert:

- **(a)** `stateFile`, `log.file`, `projectRoutesFile` sind lokale relative Pfade — nicht zwischen Maschinen geteilt.
- **(b)** Der Dedup-Key in `Copy-NewFiles` ist der vollständige, aufgelöste lokale Pfad (`$item.FullName.ToLowerInvariant()`, `scripts/DocFlowEngine.psm1:659`). Da Quellpfade Wildcards für Benutzername/Tenant enthalten, ergibt dieselbe Datei auf zwei Maschinen zwei unterschiedliche Keys — **das eigentliche Kernproblem**.
- **(c)** `project-routes.txt` liegt im Git-Repo, wird aber zur Laufzeit beschrieben → Divergenz zwischen unabhängigen Klonen.

Für den Sync der Laufzeitdaten (State-Datei, Registry, Lock) gibt es zwei grundsätzliche Optionen:

| Kriterium | OneDrive/SharePoint-Sync (Konzept aus `MULTI-MACHINE-SETUP.md`) | Git-Sync für Laufzeitdaten |
|---|---|---|
| Vorhandene Infrastruktur | Bereits im Einsatz — die Quellordner selbst sind schon OneDrive/SharePoint-Freigaben | Müsste neu aufgebaut werden: eigenes Remote-Repo bzw. eigener Branch nur für Laufzeitdaten |
| Konfliktverhalten bei der State-Datei | Eventual Consistency, kein Hard-Fail. Mit Lock-Datei + gestaffelten Scheduled Tasks (bereits in `MULTI-MACHINE-SETUP.md` §2 vorgeschlagen) gut beherrschbar | Git verweigert einen non-fast-forward Push. Ein unbeaufsichtigter Scheduled-Task-Lauf bliebe bei einem Konflikt stecken — ein JSON-Blob wie `.docflow-state.json` lässt sich nicht automatisch mergen |
| Auth/Secrets | Keine zusätzlichen Zugangsdaten nötig | PAT oder SSH-Key müsste auf jeder Schüler-/Ausbilder-Maschine hinterlegt werden — im Schulumfeld ein zusätzliches, heikles Verteilungsproblem |
| Löst Root Cause (b) (pfadabhängiger Dedup-Key)? | Nein von selbst — der Code-Fix (relativer Key statt `FullName`) ist so oder so nötig | Ebenfalls nicht von selbst nötig |
| Umsetzungsaufwand | Klein: 2–3 gezielte Codeänderungen (relativer Key, Pfade in Config auf Shared-Folder umbiegen, Lock-Datei) | Groß: Git-Wrapper um jeden Lauf (pull/commit/push), Retry-/Merge-Strategie, Provisioning der Credentials auf allen Maschinen |
| Fehlerbild bei Netzwerkproblemen | OneDrive synchronisiert im Hintergrund nach, ggf. "Conflicted Copy"-Datei | Fehlgeschlagener `git push` lässt lokale Commits zurück → Divergenz, falls nicht explizit behandelt |

**Entscheidung: OneDrive/SharePoint-Sync.** Der in `MULTI-MACHINE-SETUP.md` skizzierte Ansatz ist klar **leichter umsetzbar** und wird beibehalten:

- Er nutzt Infrastruktur, die im Setup ohnehin schon vorhanden ist (die Schüler laden bereits über OneDrive/SharePoint hoch).
- Er braucht kein Secret-/Credential-Management für Git-Remotes auf potenziell vielen, IT-seitig verwalteten Schulrechnern.
- Für eine kleine, unattended laufende JSON-State-Datei ist "eventual consistency + Lock-Datei" robuster als Gits "fail closed bei Divergenz" — ein hängender Scheduled Task ist schwerer zu diagnostizieren als eine kurzzeitig veraltete State-Datei.

Ein Git-Sync für Laufzeitdaten würde sich nur lohnen, wenn eine **Versionshistorie der State-Änderungen** (Audit-Trail) explizit gewünscht wäre, oder wenn OneDrive/SharePoint gar nicht zur Verfügung stünde. Beides ist hier nicht der Fall — Git bleibt wie bisher nur für die **Code-Verteilung** zuständig (Punkt 6 in `MULTI-MACHINE-SETUP.md` §2), nicht für Laufzeitdaten.

**Umsetzung** (Details siehe `MULTI-MACHINE-SETUP.md` §3, hier nur referenziert):
1. ✅ Relativer Dedup-Key in `Copy-NewFiles` (`scripts/DocFlowEngine/CopyForward.ps1`): Key ist jetzt `"$($source.path)|<relativer Pfad>"` statt `$item.FullName` — stabil über Rechner/Benutzernamen hinweg.
2. ✅ `stateFile`/`log.file`/`projectRoutesFile`/`reviewMarker.kuerzelRoutesFile`/`lockFile` zeigen in `config/docflow-config.psd1` auf den geteilten `_DocFlowEngine-Shared`-Ordner; `.gitignore` ergänzt.
3. ✅ Lock-Mechanismus (`scripts/DocFlowEngine/Lock.ps1`, `Lock-DocFlowRun`/`Unlock-DocFlowRun`).
4. ✅ `defaultNameFormat = '{date}_{originalName}'` + Ziel-Existenz-Check in `Copy-NewFiles` (kopiert nicht mehr blind mit `-Force`, sondern überspringt und loggt, wenn die Zieldatei schon existiert).
5. ⏳ Gestaffelte Scheduled Tasks pro Maschine — reine Betriebs-/Deployment-Maßnahme, bleibt manuell einzurichten.

**Korrektur beim Implementieren:** `Get-DocFlowRelativePath` (`scripts/DocFlowEngine/Common.ps1`) nutzte ursprünglich `[Uri]::MakeRelativeUri`. Das funktioniert nur zuverlässig mit Windows-Pfaden (`C:/...`) — ein POSIX-Pfad wie `/tmp/...` (Linux/macOS mit PowerShell 7+, laut README ebenfalls unterstützt) wird von .NET ohne `file://`-Schema nicht als absolute URI erkannt und wirft eine Exception. Da diese Funktion jetzt für den Dedup-Key bei **jeder** Datei läuft (vorher nur optional bei `preserveSubfolders`), wurde sie auf reine, plattformunabhängige String-Verarbeitung umgestellt.

---

## 2. Erweiterung der Namenskonvention-Prüfung

### 2a. Pro-Datei-Fehlerhinweis statt geteilter Ordner-Hinweisdatei

**Ist-Zustand:** `Write-NamingConventionHint` (`scripts/DocFlowEngine.psm1:472-501`) schreibt eine **einzige, geteilte** Hinweisdatei `BITTE_NAMENSKONVENTION_BEACHTEN.txt` pro Quellordner. Das Schreiben ist `Test-Path`-geschützt (`psm1:484-486`) — sobald die Datei einmal existiert, wird sie nicht erneuert. Das hat zwei Schwächen:
- Kein Bezug zur konkreten fehlerhaften Datei — bei mehreren falsch benannten Dateien im selben Ordner bleibt unklar, welche gemeint ist.
- Kommt eine weitere falsch benannte Datei später hinzu, wird kein neuer Hinweis erzeugt, weil die generische Hinweisdatei schon existiert.

**Vorschlag:** Zusätzlich zu (oder anstelle von) der geteilten Hinweisdatei pro fehlerhafter Datei eine eigene, individuelle Hinweisdatei erzeugen, z. B.:

```
<originalDateiname>.NAMENSKONVENTION-FEHLER.txt
```

Inhalt (Template, analog zum bestehenden `namingConventionHint.message`-Mechanismus in `docflow-config.psd1:62-66`):

```
Die Datei "<originalDateiname>" entspricht nicht der erwarteten Namenskonvention:
  <initialen>[_v<version>]_<praefix>_<suffix>_<aufgabennummer>

Beispiel: pke_Java_Suffix_abc.pdf  oder  pke_v2_Java_Suffix_abc.pdf

Bitte die Datei entsprechend umbenennen und erneut hochladen.
```

**Voraussetzung:** Das neue Hinweisdateimuster muss über `excludePatterns` von der Quell-Erkennung ausgeschlossen werden (z. B. `*.NAMENSKONVENTION-FEHLER.txt`), analog zum bestehenden Ausschluss der generischen Hinweisdatei (`docflow-config.psd1:19`) — sonst würde die Hinweisdatei selbst beim nächsten Lauf als "neue Quelldatei" fehlinterpretiert.

**Entscheidung:** Der bisherige, ordnerweite Sammelhinweis (`BITTE_NAMENSKONVENTION_BEACHTEN.txt`) wird durch die Pro-Datei-Variante **ersetzt** (nicht parallel betrieben). `Write-NamingConventionHint` (`psm1:472-501`) wird entsprechend umgebaut: statt eines einzigen, `Test-Path`-geschützten Ordnerhinweises erzeugt sie künftig pro fehlerhafter Datei die individuelle `<originalDateiname>.NAMENSKONVENTION-FEHLER.txt`.

### 2b. "Korrigiert"-Rücklauf-Workflow

**Ziel:** Wenn der Ausbilder im Zielordner eine geprüfte Datei umbenennt und dabei ein Kürzel-Suffix wie `_k-<kürzel>` anhängt (z. B. `2026-08-25_pke_Java_Suffix_abc_k-ml.pdf`), soll DocFlowEngine das erkennen und die Datei automatisch in einen `Korrigiert`-Unterordner **direkt im Schülerordner** kopieren (Original im Zielordner bleibt erhalten). Wichtig: **nicht** zurück in den aufgabenspezifischen Zielort, sondern gesammelt an einer Stelle pro Schüler — alle korrigierten Dateien dieses Schülers, egal von welcher Aufgabe, landen im selben `Korrigiert`-Unterordner.

**Rahmenbedingungen (vom Nutzer bestätigt):**
- Kürzel sind 3-stellige Buchstabencodes (a–z), **eindeutig und genau einmal pro Schüler vergeben** — nicht pro Aufgabe neu. Das schließt Mehrdeutigkeiten aus: ein Kürzel zeigt immer auf genau einen Schülerordner.
- Der Schülerordner ist bereits derselbe Ordner, den DocFlowEngine heute als `sources[]`-Eintrag abscannt — keine zusätzliche Ordnerebene nötig.
- **Kernproblem:** Der Quellordner-Pfad enthält den ausgeschriebenen Schülernamen (z. B. `.../Max Mustermann/...`), nicht das Kürzel. Aus dem Kürzel im Dateinamen lässt sich der Zielpfad also nicht direkt ableiten — es braucht eine Kürzel→Schülerordner-Zuordnung.

**Konzeptioneller Ablauf:**

```
Zielordner (Ausbilder prüft, benennt um)
   <datum>_<initialen>_<praefix>_<suffix>_<aufgabennummer>_k-<kuerzel>.pdf
                    │
                    │  DocFlowEngine erkennt Marker "_k-<kuerzel>" am Dateiende
                    ▼
   Kürzel aus Dateiname extrahieren
                    │
                    ▼
   Schülerordner über Kuerzel-Registry nachschlagen (kuerzel-routes.txt)
                    │
                    ▼
   Kopie nach: <Schülerordner>/Korrigiert/<Zieldateiname>
```

**Bausteine (Vorschlag):**

1. **Neue, automatisch geführte Registry** `config/kuerzel-routes.txt` (Format wie das bestehende `config/project-routes.txt`: `key=value`-Zeilen, `#`-Kommentare), z. B.:
   ```
   pke=C:\Users\p0kretzer\OneDrive - D...\SchuelerMaterial\Max Mustermann
   ```
   Ein Eintrag pro Kürzel, **einmalig** angelegt — passend dazu, dass ein Kürzel dauerhaft und eindeutig einem Schüler gehört.

2. **Neue Funktion** `Register-Kuerzel` (analog zu `Register-PraefixSuffix`, `scripts/DocFlowEngine/Naming.ps1`; `Register-Kuerzel` selbst liegt in `scripts/DocFlowEngine/CopyBack.ps1`): wird im bestehenden Vorwärtslauf (`Copy-NewFiles`, `scripts/DocFlowEngine/CopyForward.ps1`) aufgerufen, sobald eine Quelldatei erfolgreich verarbeitet wurde. Extrahiert `initials`/Kürzel über die neue Hilfsfunktion `Get-FileInitials` (dieselbe .NET-Match-Technik wie `Get-TargetFileName`, damit eine vorhandene, aber leere optionale Gruppe korrekt erkannt wird) und trägt — **nur beim allerersten Vorkommen dieses Kürzels** — den Quellordner-Pfad in `kuerzel-routes.txt` ein (Dedup-Prüfung analog zu `Register-PraefixSuffix`). Kein manueller Pflegeaufwand — die Liste baut sich beim normalen Betrieb von selbst auf, sobald jeder Schüler einmal etwas hochgeladen hat.

   **Korrektur beim Implementieren:** Als Quellordner wird bewusst `$item.DirectoryName` (der unmittelbare Ordner der jeweiligen Datei) registriert, **nicht** die aufgelöste Quellwurzel `$resolvedSourcePath` aus `sources[]`. Grund: Die reale `sources[]`-Konfiguration hat aktuell nur **einen** rekursiv gescannten, gemeinsamen Austauschordner (`FI*/Austauschordner/`) für alle Schüler — dessen Wurzel wäre für jede Datei identisch und würde alle Kürzel auf denselben Ordner abbilden. `$item.DirectoryName` liefert dagegen den tatsächlichen, ggf. schülerspezifischen Unterordner, in dem die konkrete Datei gefunden wurde, und funktioniert unabhängig davon, ob es einen eigenen Schülerunterordner gibt oder alle Dateien flach in einem Ordner liegen.

3. **Neue Funktion** `Get-KuerzelRoutes` (analog zu `Get-PraefixSuffixRegistry`; beide in `scripts/DocFlowEngine/CopyBack.ps1` bzw. `Naming.ps1`): lädt `kuerzel-routes.txt` in eine Lookup-Tabelle (Kürzel → Schülerordner-Pfad).

4. **Config-Element** `reviewMarker` in `docflow-config.psd1`:
   ```powershell
   reviewMarker = @{
       enabled              = $true
       pattern              = '_k-(?<kuerzel>[A-Za-z]{3})$'
       korrigiertFolderName = 'Korrigiert'
       kuerzelRoutesFile    = '<geteilter Ordner>/kuerzel-routes.txt'
   }
   ```
   Formatbeispiel/Vorlage der Registry-Datei: `config/kuerzel-routes.example.txt` (die tatsächlich genutzte Datei liegt im geteilten Ordner, nicht im Git-Repo — siehe Abschnitt 1).

5. **Neue Funktion** `Copy-ReviewedFiles` (analog zu `Copy-NewFiles`, in `scripts/DocFlowEngine/CopyBack.ps1`): durchsucht `aufgabenRoot` rekursiv nach Dateien, deren Name (ohne Extension) auf `reviewMarker.pattern` matcht — bewusst `aufgabenRoot`, nicht die generischen `targets[]`, da nur dort Dateien mit `initials`/`praefix`/`suffix`-Namensschema landen, für die ein Kürzel-Marker überhaupt Sinn ergibt. Extrahiert `kuerzel`, schlägt über `Get-KuerzelRoutes` den Schülerordner nach und kopiert nach `<Schülerordner>/Korrigiert/<Zieldateiname>`. Die Datei wird **kopiert**, nicht verschoben — das Original bleibt für den Ausbilder erhalten.

6. **Randfall — unbekanntes Kürzel:** Falls ein Kürzel in `_k-<kuerzel>` nicht in `kuerzel-routes.txt` steht (z. B. Tippfehler des Ausbilders, oder die Registry wurde noch nie für diesen Schüler befüllt), kann keine Rückkopie erfolgen. Umgesetzt über `unknownKuerzelHint`-Konfiguration: analog zum Namenskonvention-Hinweis (Abschnitt 2a) wird eine individuelle Hinweisdatei (`<Dateiname>.KUERZEL-UNBEKANNT.txt`) neben der Datei abgelegt statt sie stillschweigend zu überspringen.

7. **Korrektheit:** Der `Korrigiert`-Unterordner liegt **innerhalb** des Schülerordners, der zugleich als `sources[]`-Eintrag gescannt wird. Statt eines `excludePatterns`-Eintrags (der in `Get-SourceFiles` nur gegen den Dateinamen, nicht den Pfad matcht) prüft `Copy-NewFiles` deshalb pro Datei explizit, ob einer ihrer Verzeichnis-Segmente `korrigiertFolderName` entspricht (`Test-DocFlowInsideNamedFolder`), und überspringt sie in dem Fall — sonst würde die zurückkopierte Datei beim nächsten Lauf fälschlich erneut als "neue" Quelldatei erkannt.

8. **Dedup:** State-Sektion `reviewedFiles` in der bestehenden State-Datei, analog zum bestehenden Dedup-Mechanismus in `Copy-NewFiles`, damit dieselbe Rückkopie nicht bei jedem Lauf wiederholt wird. Da Kürzel eindeutig und dauerhaft sind, gibt es hier — anders als in einer früheren Überlegung — keine Mehrdeutigkeit bei mehreren Aufgaben desselben Schülers.

---

## 3. Sprachwahl: PowerShell behalten, Python/Ansible nur punktuell

`scripts/DocFlowEngine.psm1` ist mit ~817 Zeilen bereits eine große Einzeldatei, und die oben skizzierten Erweiterungen (Pro-Datei-Hinweise, Korrigiert-Rücklauf, Multi-Machine-Fixes) würden sie weiter wachsen lassen.

| Option | Bewertung |
|---|---|
| **PowerShell behalten, modularisieren** | Kein neues Laufzeit-Dependency: Windows-Schulrechner bringen PowerShell 5.1 bereits mit (`#Requires -Version 5.1`). Aufgeteilt in Teilmodule unter `scripts/DocFlowEngine/` (`Common.ps1`, `Config.ps1`, `State.ps1`, `Lock.ps1`, `Naming.ps1`, `CopyForward.ps1`, `CopyBack.ps1`), die `scripts/DocFlowEngine.psm1` per Dot-Sourcing einbindet. Die zuvor nur in README referenzierte, aber fehlende `tests/DocFlowEngine.Tests.ps1` existiert jetzt mit Pester-Tests für Namensregeln, Dedup-Key, Korrigiert-Rücklauf und Lock-Mechanismus. |
| **Python** | Mächtigere Sprache, bessere Testbarkeit (pytest), aber: erfordert einen installierten Python-Runtime auf jeder Schüler-/Ausbilder-Maschine. Auf verwalteten Schulrechnern (typischerweise ohne Admin-Rechte für Schüler) ist das ein reales Deployment-Hindernis, das bei PowerShell (bereits vorhanden) nicht besteht. Sinnvoll höchstens als **optionales, separates** Hilfswerkzeug (z. B. ein Reporting-/Auswertungsskript über die State-Datei), falls ein Python-Runtime auf den Zielrechnern nachweislich vorhanden ist — nicht als Ersatz der Kernlogik. |
| **Ansible** | Schlechte Passung für dieses Problem: Ansible orchestriert Konfigurations-/Deployment-Zustand über SSH/WinRM von einem Control-Node aus, ersetzt aber nicht die laufende Datei-Kopier-/Umbenennungslogik. Allenfalls für die **Code-Verteilung** denkbar (vgl. `MULTI-MACHINE-SETUP.md` §2 Punkt 6), setzt aber WinRM-Zugriff auf alle Schüler-/Ausbilder-Rechner von einem zentralen Control-Node aus voraus. Ob eine solche zentrale Administrationsmöglichkeit im Schulumfeld überhaupt besteht, ist unklar (siehe Offene Punkte). |

**Entscheidung: nur PowerShell**, keine Migration der Kernlogik. Als konkreter nächster Schritt gegen das wachsende Einzelskript: Modularisierung in Teilmodule (siehe oben) + Nachrüsten von Pester-Tests. Python/Ansible werden nicht eingeführt, auch nicht als optionale Ergänzung — die Zeilen zu Python/Ansible in der Tabelle oben dokumentieren nur die Abwägung, die zu dieser Entscheidung geführt hat.

---

## 4. Entscheidungsstand

Alle drei Grundsatzfragen sind entschieden:

1. **Multi-Machine-Setup:** OneDrive/SharePoint-Sync (Abschnitt 1) — nicht Git-Sync.
2. **Namenskonvention-Hinweis:** Pro-Datei-Fehlerhinweis (Abschnitt 2a) ersetzt den alten Sammelhinweis vollständig.
3. **Korrigiert-Rücklauf** (Abschnitt 2b): Ordnername `Korrigiert`, Zuordnung Kürzel→Schülerordner über eine automatisch geführte Registry (`kuerzel-routes.txt`, analog `project-routes.txt`), befüllt beim ersten verarbeiteten Upload je Kürzel. Der Schülerordner ist identisch mit dem bereits konfigurierten `sources[]`-Eintrag, keine weitere Ordnerebene nötig. Kürzel sind eindeutige, dauerhafte 3-Buchstaben-Codes pro Schüler — daher keine Mehrdeutigkeit bei mehreren Aufgaben.
4. **Sprachwahl:** Nur PowerShell, modularisiert in Teilmodule (Abschnitt 3) — kein Python, kein Ansible.
5. **Präfix/Suffix-Whitelist** (Abschnitt 5, Follow-up): `project-routes.txt` ist keine automatisch wachsende Registry mehr, sondern eine von Hand gepflegte Whitelist. Unbekannter Präfix/Suffix → Namenskonvention-Fehler statt automatischer Aufnahme.

---

## 5. Präfix/Suffix als feste Whitelist statt automatischer Registrierung (Follow-up)

**Anlass:** Nutzer-Feedback nach der ersten Umsetzung: (a) Bestätigung, dass fehlender Präfix/Suffix bereits korrekt zu einer Hinweisdatei beim Schüler führt (siehe Abschnitt 2a/2b — war schon so umgesetzt), und (b) die neue Anforderung, dass **nur** die in `project-routes.txt` bereits hinterlegten Präfixe/Suffixe akzeptiert werden sollen — nicht mehr wie zuvor automatisch um jeden neu auftauchenden Wert erweitert.

**Ist-Zustand vor diesem Follow-up:** `Get-FilePraefixSuffix` akzeptierte jeden Dateinamen, der syntaktisch zum Schema `initialen_praefix_suffix_aufgabennummer` passte — der konkrete Wert von Präfix/Suffix wurde nicht gegen `project-routes.txt` geprüft. `Register-PraefixSuffix` trug jeden neuen Wert automatisch in die Registry ein. Damit konnte im Prinzip jedes beliebige Wort als "Fach" in `aufgabenRoot/<Wort>/...` landen.

**Umsetzung:**
- Neue Funktion `Test-DocFlowPraefixSuffixKnown` (`scripts/DocFlowEngine/Naming.ps1`): prüft, ob sowohl Präfix als auch Suffix bereits einzeln als `praefix=`/`suffix=`-Zeile in der geladenen Registry stehen.
- `Copy-NewFiles` (`scripts/DocFlowEngine/CopyForward.ps1`) routet eine Datei nur noch nach `aufgabenRoot`, wenn `Test-DocFlowPraefixSuffixKnown` `true` liefert. Andernfalls greift derselbe Pro-Datei-Hinweismechanismus wie beim komplett fehlenden Präfix/Suffix (Abschnitt 2a) — die Meldung kann optional `{praefix}`/`{suffix}` referenzieren, um konkret zu benennen, was unbekannt ist.
- `Register-PraefixSuffix` (automatische Registrierung) wurde **entfernt**, nicht nur deaktiviert — es gab nach der Umstellung keinen Aufrufer mehr dafür.
- Ist gar keine Registry konfiguriert (`projectRoutesFile` leer/nicht gesetzt), bleibt es beim alten, permissiven Verhalten (jeder syntaktisch passende Präfix/Suffix wird akzeptiert) — die Whitelist ist also ein Opt-in über das Vorhandensein von `projectRoutesFile`, kein Zwang.
- `config/project-routes.txt` und `config/docflow-config.psd1` entsprechend umkommentiert: die Datei muss jetzt **von Hand** gepflegt werden, wenn ein neues Fach/Thema hinzukommt.

**Getestet:** drei neue Pester-Tests (bekannter Präfix/Suffix → Routing; unbekannter Präfix/Suffix → Hinweisdatei, keine Kopie, keine Registrierung; keine Registry konfiguriert → altes permissives Verhalten) sowie ein manueller End-to-End-Lauf mit drei Dateien (bekannte Kombination, unbekannter Suffix, unbekannter Präfix) — Whitelist griff in beiden Fehlerfällen korrekt, `project-routes.txt` blieb unverändert.

Damit sind alle ursprünglich offenen Punkte sowie das Follow-up-Feedback geklärt.
