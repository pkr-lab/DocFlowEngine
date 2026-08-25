@{
    # DocFlowEngine configuration
    #
    # Eingehende Aufgaben-Dateien folgen dem Schema:
    #   <initialen>[_v<versionsnummer>]_<praefix>_<suffix>_<aufgabennummer>
    #   (z. B. pke_Java_Suffix_abc oder pke_v2_Java_Suffix_abc für eine erneute Abgabe)
    # Beim Kopieren wird das Upload-Datum vorangestellt:
    #   <datum>_<initialen>[_v<versionsnummer>]_<praefix>_<suffix>_<aufgabennummer>
    # Die Versionsnummer ist optional - ohne sie funktioniert das Schema wie bisher.
    #
    # "C:/Users/p0*/OneDrive - D*/SharePoint" verwendet Wildcards, da Benutzername
    # und OneDrive-Mandantenname je Gerät variieren können.

    sources = @(
        @{
            path             = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/FI*/Austauschordner/'
            recursive        = $true
            includePatterns  = @('*.pdf', '*.docx', '*.doc', '*.xlsx', '*.java', '*.zip', '*.py', '*.txt', '*.md', '*.csv', '*.pptx', '*.png', '*.jpg', '*.jpeg')
            # ~$* sind temporäre Office-Dateien. *.NAMENSKONVENTION-FEHLER.txt und
            # *.KUERZEL-UNBEKANNT.txt sind DocFlowEngines eigene Pro-Datei-Hinweise
            # (siehe namingConventionHint/unknownKuerzelHint weiter unten) und dürfen
            # nicht als eigene Quelldatei erkannt werden.
            excludePatterns  = @('.*', 'Thumbs.db', 'desktop.ini', '~$*', '*.NAMENSKONVENTION-FEHLER.txt', '*.KUERZEL-UNBEKANNT.txt')
        }
    )

    targets = @(
        @{
            path               = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/docs/archive'
            createIfMissing    = $true
            preserveSubfolders = $false
        }
    )

    # Wurzelverzeichnis für die Aufgaben-Ablage. Dateien, deren Name dem
    # Präfix/Suffix-Schema entspricht, werden nach
    # <aufgabenRoot>/<Präfix>/<Suffix>/ kopiert statt in die obigen 'targets'.
    aufgabenRoot = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/docs/Aufgaben'

    namingConventions = @(
        @{
            name        = 'Initials-Praefix-Suffix-Aufgabe'
            description = 'Format initialen[_v<version>]_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc oder pke_v2_Java_Suffix_abc für eine erneute Abgabe).'
            match       = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename      = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
        },
        @{
            name        = 'Date-prefix'
            description = 'Wenn der Dateiname mit einem Datum beginnt, wird dieses Datum erhalten.'
            match       = '^(?<date>\d{4}-\d{2}-\d{2})[_\s-]+(?<name>.+)$'
            rename      = '{date}_{name}'
        },
        @{
            name        = 'Default'
            description = 'Fallback-Regel: Zeitstempel und Originalname.'
            match       = '^(?<name>.+)$'
            rename      = '{timestamp}_{name}'
        }
    )

    # Wird bei einer Quelle mit 'aufgabenRoot' ausgewertet: Passt eine Datei zu
    # keiner Regel mit Praefix/Suffix-Gruppen (siehe oben), ODER ist der erkannte
    # Praefix/Suffix nicht in project-routes.txt hinterlegt (siehe unten), wird sie
    # NICHT kopiert. Stattdessen legt DocFlowEngine direkt neben der betroffenen
    # Datei eine eigene Hinweis-Textdatei an (<Dateiname>.NAMENSKONVENTION-FEHLER.txt),
    # die zur korrekten Umbenennung und zum erneuten Hochladen auffordert. Ein
    # Hinweis pro Datei statt einer geteilten Ordner-Hinweisdatei, damit bei
    # mehreren fehlerhaften Dateien im selben Ordner erkennbar bleibt, welche
    # gemeint ist (siehe ERWEITERUNGSKONZEPT.md, Abschnitt 2a). Die Meldung darf
    # optional {praefix}/{suffix} referenzieren (leer, wenn das Namensschema gar
    # nicht erst gematcht hat).
    namingConventionHint = @{
        enabled        = $true
        fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'
        message        = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema initialen[_v<version>]_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc oder bei einer erneuten Abgabe pke_v2_Java_Suffix_abc). Bitte benenne die Datei entsprechend um und lade sie erneut hoch.'
    }

    # "Korrigiert"-Rücklauf (siehe ERWEITERUNGSKONZEPT.md, Abschnitt 2b): Benennt
    # ein Ausbilder eine geprüfte Datei unterhalb von 'aufgabenRoot' um und hängt
    # das Suffix "_k-<kürzel>" an (z. B. "..._abc_k-pke.pdf"), kopiert DocFlowEngine
    # sie automatisch in <Schülerordner>/<korrigiertFolderName>/ zurück. Die
    # Zuordnung Kürzel -> Schülerordner wird in kuerzelRoutesFile automatisch beim
    # normalen Hochladen befüllt (einmalig pro Kürzel, siehe project-routes.txt-
    # Mechanismus).
    reviewMarker = @{
        enabled              = $true
        pattern              = '_k-(?<kuerzel>[A-Za-z]{3})$'
        korrigiertFolderName = 'Korrigiert'
        kuerzelRoutesFile    = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/kuerzel-routes.txt'
    }

    # Hinweis, falls beim Korrigiert-Rücklauf ein Kürzel in _k-<kürzel> auftaucht,
    # das noch keinem Schülerordner zugeordnet werden konnte (z. B. Tippfehler).
    unknownKuerzelHint = @{
        enabled = $true
        message = 'Die Datei "{fileName}" wurde mit dem Kürzel "{kuerzel}" markiert, aber diesem Kürzel ist noch kein Schülerordner bekannt. Bitte Kürzel prüfen, oder den Schüler einmal regulär hochladen lassen, damit es automatisch registriert wird.'
    }

    # Feste Liste der erlaubten Präfixe und Suffixe (Fächer/Themen). Nur Dateien,
    # deren Präfix UND Suffix hier bereits als eigene Zeile ("praefix=..."/
    # "suffix=...") stehen, werden nach aufgabenRoot geroutet - ein noch nicht
    # gelisteter Präfix/Suffix wird NICHT mehr automatisch aufgenommen, sondern wie
    # eine falsche Namenskonvention behandelt (siehe namingConventionHint oben).
    # Neue Fächer/Themen müssen von Hand in dieser Datei ergänzt werden. Sie liegt
    # bewusst im bereits über OneDrive/SharePoint geteilten Ordner statt im
    # Git-Repo, damit sie auf mehreren Rechnern denselben Stand hat (siehe
    # MULTI-MACHINE-SETUP.md, Baustein 2). config/project-routes.txt im Repo dient
    # nur als Startbestand/Beispiel und muss einmalig dorthin kopiert werden.
    projectRoutesFile = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/project-routes.txt'

    # Deterministisch statt {timestamp}: nötig für den Ziel-Existenz-Check und den
    # Multi-Machine-Betrieb (siehe MULTI-MACHINE-SETUP.md, Baustein 5) - ein
    # Zeitstempel würde bei jedem Lauf einen neuen, nicht wiedererkennbaren Namen
    # erzeugen.
    defaultNameFormat = '{date}_{originalName}'
    stateFile         = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/.docflow-state.json'

    # Lock-Datei gegen gleichzeitige Schreibzugriffe mehrerer Rechner auf die
    # geteilten Dateien oben (siehe MULTI-MACHINE-SETUP.md, Baustein 3). Auf
    # $null setzen, um Locking zu deaktivieren (Einzelrechner-Betrieb).
    lockFile           = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/.docflow-lock'
    lockTimeoutMinutes = 15

    log = @{
        level = 'Info'
        file  = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/docflow.log'
    }
}
