@{
    sources = @(
        @{
            path             = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/FI*/Austauschordner/'
            recursive        = $true
            includePatterns  = @('*.pdf', '*.docx', '*.doc', '*.xlsx', '*.java', '*.zip', '*.py', '*.txt', '*.md', '*.csv', '*.pptx', '*.png', '*.jpg', '*.jpeg')
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

    namingConventionHint = @{
        enabled        = $true
        fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'
        message        = 'Deine Datei "{fileName}" entspricht nicht dem vorgegebenen Namensschema initialen[_v<version>]_praefix_suffix_aufgabennummer (z. B. pke_Java_Suffix_abc oder bei einer erneuten Abgabe pke_v2_Java_Suffix_abc). Bitte benenne die Datei entsprechend um und lade sie erneut hoch.'
    }

    reviewMarker = @{
        enabled              = $true
        pattern              = '_k-[A-Za-z0-9]+$'
        korrigiertFolderName = 'Korrigiert'
        kuerzelRoutesFile    = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/kuerzel-routes.txt'
    }

    unknownKuerzelHint = @{
        enabled = $true
        message = 'Die Datei "{fileName}" ist als Korrektur markiert, aber für das im Dateinamen erkannte Kürzel "{kuerzel}" ist noch kein Schülerordner bekannt. Bitte prüfen, oder den Schüler einmal regulär hochladen lassen, damit es automatisch registriert wird.'
    }

    projectRoutesFile     = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/project-routes.txt'
    projectRoutesSeedFile = './config/project-routes.txt'

    defaultNameFormat = '{date}_{originalName}'
    stateFile         = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/.docflow-state.json'

    lockFile           = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/.docflow-lock'
    lockTimeoutMinutes = 15

    log = @{
        level = 'Info'
        file  = 'C:/Users/p0*/OneDrive - D*/IT-Ausbildung - Jahrgangsordner/SchuelerMaterial/_DocFlowEngine-Shared/docflow.log'
    }
}
