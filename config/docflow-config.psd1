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
            excludePatterns  = @('.*', 'Thumbs.db', 'desktop.ini', '~$*', 'BITTE_NAMENSKONVENTION_BEACHTEN.txt')  # ~$* sind temporäre Office-Dateien
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
    # keiner Regel mit Praefix/Suffix-Gruppen (siehe oben), wird sie NICHT kopiert.
    # Stattdessen legt DocFlowEngine im selben Ordner wie die Datei eine
    # Hinweis-Textdatei an, die zur korrekten Umbenennung und zum erneuten
    # Hochladen auffordert.
    namingConventionHint = @{
        enabled  = $true
        fileName = 'BITTE_NAMENSKONVENTION_BEACHTEN.txt'
        message  = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema initialen[_v<version>]_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc oder bei einer erneuten Abgabe pke_v2_Java_Suffix_abc). Bitte benenne die Datei entsprechend um und lade sie erneut hoch.'
    }

    # Registry aller bisher erkannten Präfixe und Suffixe. DocFlowEngine ergänzt
    # diese Datei automatisch um neu erkannte Werte (siehe config/project-routes.txt).
    projectRoutesFile = './config/project-routes.txt'

    defaultNameFormat = '{timestamp}_{originalName}'
    stateFile         = './.docflow-state.json'

    log = @{
        level = 'Info'
        file  = './docflow.log'
    }
}
