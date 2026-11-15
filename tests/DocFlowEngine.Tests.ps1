#Requires -Version 5.1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../scripts/DocFlowEngine.psm1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-DocFlowRelativePath' {
    It 'berechnet den relativen Pfad plattformunabhängig (ohne Uri)' {
        $base = Join-Path $TestDrive 'source'
        $full = Join-Path $base 'sub/datei.pdf'
        $relative = Get-DocFlowRelativePath -BasePath $base -FullPath $full
        $expected = Join-Path 'sub' 'datei.pdf'
        $relative | Should -Be $expected
    }
}

Describe 'Get-TargetFileName' {
    BeforeAll {
        $rules = @(
            @{
                name   = 'Initials-Praefix-Suffix-Aufgabe'
                match  = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
                rename = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
            }
        )
    }

    It 'ersetzt eine nicht vorhandene optionale Gruppe (versiontag) durch einen leeren String' {
        $file = New-Item -Path (Join-Path $TestDrive 'pke_Java_Suffix_abc.pdf') -ItemType File -Force
        $name = Get-TargetFileName -File $file -Rules $rules -DefaultFormat '{timestamp}_{originalName}'
        $name | Should -Not -Match '\{versiontag\}'
        $name | Should -Match '^\d{8}_pke_Java_Suffix_abc\.pdf$'
    }

    It 'übernimmt eine vorhandene Versionsangabe' {
        $file = New-Item -Path (Join-Path $TestDrive 'pke_v2_Java_Suffix_abc.pdf') -ItemType File -Force
        $name = Get-TargetFileName -File $file -Rules $rules -DefaultFormat '{timestamp}_{originalName}'
        $name | Should -Match '^\d{8}_pke_v2_Java_Suffix_abc\.pdf$'
    }
}

Describe 'Get-FileInitials' {
    BeforeAll {
        $rules = @(
            @{
                match = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            }
        )
    }

    It 'extrahiert die initials-Gruppe' {
        $file = New-Item -Path (Join-Path $TestDrive 'ems_Python_Einfuehrung_xyz.pdf') -ItemType File -Force
        Get-FileInitials -File $file -Rules $rules | Should -Be 'ems'
    }

    It 'gibt $null zurück, wenn keine Regel matcht' {
        $file = New-Item -Path (Join-Path $TestDrive 'komplett anders.pdf') -ItemType File -Force
        Get-FileInitials -File $file -Rules $rules | Should -BeNullOrEmpty
    }
}

Describe 'Write-NamingConventionHint (Pro-Datei-Hinweis)' {
    It 'erzeugt eine individuelle Hinweisdatei pro fehlerhafter Datei statt einer geteilten' {
        $dir = Join-Path $TestDrive 'hints'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        $file1 = New-Item -Path (Join-Path $dir 'a.pdf') -ItemType File -Force
        $file2 = New-Item -Path (Join-Path $dir 'b.pdf') -ItemType File -Force
        $hintConfig = @{ enabled = $true; fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'; message = 'Fehler bei {fileName}' }

        Write-NamingConventionHint -File $file1 -HintConfig $hintConfig
        Write-NamingConventionHint -File $file2 -HintConfig $hintConfig

        $hint1 = Join-Path $dir 'a.pdf.NAMENSKONVENTION-FEHLER.txt'
        $hint2 = Join-Path $dir 'b.pdf.NAMENSKONVENTION-FEHLER.txt'
        Test-Path $hint1 | Should -BeTrue
        Test-Path $hint2 | Should -BeTrue
        Get-Content -Path $hint1 -Raw | Should -Match 'a\.pdf'
    }

    It 'überschreibt eine bereits vorhandene Hinweisdatei nicht erneut' {
        $dir = Join-Path $TestDrive 'hints-existing'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        $file = New-Item -Path (Join-Path $dir 'a.pdf') -ItemType File -Force
        $hintPath = Join-Path $dir 'a.pdf.NAMENSKONVENTION-FEHLER.txt'
        Set-Content -Path $hintPath -Value 'ALT'
        $hintConfig = @{ enabled = $true; fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'; message = 'NEU' }

        Write-NamingConventionHint -File $file -HintConfig $hintConfig

        Get-Content -Path $hintPath -Raw | Should -Match 'ALT'
    }
}

Describe 'Get-KuerzelRoutes / Register-Kuerzel' {
    It 'registriert ein neues Kürzel genau einmal in der Registry-Datei' {
        $routesFile = Join-Path $TestDrive 'kuerzel-routes.txt'
        $routes = @{}

        Register-Kuerzel -Routes $routes -RoutesFilePath $routesFile -Kuerzel 'pke' -SourcePath '/pfad/zu/Max Mustermann'
        Register-Kuerzel -Routes $routes -RoutesFilePath $routesFile -Kuerzel 'pke' -SourcePath '/anderer/pfad'

        $routes['pke'] | Should -Be '/pfad/zu/Max Mustermann'
        $lines = Get-Content -Path $routesFile
        ($lines | Where-Object { $_ -like 'pke=*' }).Count | Should -Be 1
    }

    It 'liest eine bestehende Registry-Datei case-insensitiv nach Kürzel ein' {
        $routesFile = Join-Path $TestDrive 'kuerzel-routes-read.txt'
        Set-Content -Path $routesFile -Value @('# Kommentar', 'PKE=/pfad/a', 'ems=/pfad/b')

        $routes = Get-KuerzelRoutes -Path $routesFile
        $routes['pke'] | Should -Be '/pfad/a'
        $routes['ems'] | Should -Be '/pfad/b'
    }
}

Describe 'Copy-ReviewedFiles ("Korrigiert"-Rücklauf)' {
    BeforeEach {
        $script:aufgabenRoot = Join-Path $TestDrive "aufgaben-$(New-Guid)"
        $script:studentFolder = Join-Path $TestDrive "student-$(New-Guid)"
        New-Item -Path $script:aufgabenRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:studentFolder -ItemType Directory -Force | Out-Null

        $script:reviewMarker = @{
            enabled              = $true
            pattern              = '_k-[A-Za-z0-9]+$'
            korrigiertFolderName = 'Korrigiert'
        }
        $script:rules = @(
            @{
                match = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            }
        )
        $script:kuerzelRoutes = @{ pke = $script:studentFolder }
        $script:state = @{ processed = @{}; reviewedFiles = @{} }
    }

    It 'kopiert eine mit _k-Marker versehene Datei in den Korrigiert-Unterordner des Schuelerordners' {
        $reviewedFile = Join-Path $script:aufgabenRoot '20260825_pke_Java_Suffix_abc_k-pke.pdf'
        Set-Content -Path $reviewedFile -Value 'dummy'

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules

        $expected = Join-Path (Join-Path $script:studentFolder 'Korrigiert') '20260825_pke_Java_Suffix_abc_k-pke.pdf'
        Test-Path $expected | Should -BeTrue
        Test-Path $reviewedFile | Should -BeTrue
    }

    It 'ignoriert den Text nach _k- vollstaendig - massgeblich ist das im Dateinamen selbst enthaltene Kuerzel, nicht der Marker' {
        $reviewedFile = Join-Path $script:aufgabenRoot '20260825_pke_Java_Suffix_abc_k-xyz.pdf'
        Set-Content -Path $reviewedFile -Value 'dummy'

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules

        $expected = Join-Path (Join-Path $script:studentFolder 'Korrigiert') '20260825_pke_Java_Suffix_abc_k-xyz.pdf'
        Test-Path $expected | Should -BeTrue
        ($script:state.reviewedFiles.Values | Select-Object -First 1).kuerzel | Should -Be 'pke'
    }

    It 'kopiert dieselbe Datei bei einem zweiten Lauf nicht erneut (Dedup über State)' {
        $reviewedFile = Join-Path $script:aufgabenRoot '20260825_pke_Java_Suffix_abc_k-pke.pdf'
        Set-Content -Path $reviewedFile -Value 'dummy'

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules
        $script:state.reviewedFiles.Count | Should -Be 1

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules
        $script:state.reviewedFiles.Count | Should -Be 1
    }

    It 'überspringt Dateien mit unbekanntem Kürzel und hinterlässt einen Hinweis' {
        $reviewedFile = Join-Path $script:aufgabenRoot '20260825_xyz_Python_Einfuehrung_abc_k-zzz.pdf'
        Set-Content -Path $reviewedFile -Value 'dummy'
        $unknownHint = @{ enabled = $true; message = 'Kuerzel {kuerzel} unbekannt fuer {fileName}' }

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules -UnknownKuerzelHint $unknownHint

        $script:state.reviewedFiles.Count | Should -Be 0
        Test-Path "$reviewedFile.KUERZEL-UNBEKANNT.txt" | Should -BeTrue
    }

    It 'ignoriert Dateien, die bereits im Korrigiert-Ordner selbst liegen' {
        $korrigiertDir = Join-Path $script:aufgabenRoot 'Korrigiert'
        New-Item -Path $korrigiertDir -ItemType Directory -Force | Out-Null
        $alreadyThere = Join-Path $korrigiertDir '20260825_pke_Java_Suffix_abc_k-pke.pdf'
        Set-Content -Path $alreadyThere -Value 'dummy'

        Copy-ReviewedFiles -AufgabenRoot $script:aufgabenRoot -ReviewMarker $script:reviewMarker -KuerzelRoutes $script:kuerzelRoutes -State $script:state -Rules $script:rules

        $script:state.reviewedFiles.Count | Should -Be 0
    }
}

Describe 'Sync-ProjectRoutesFromSeed' {
    It 'erstellt die Ziel-Whitelist aus dem Startbestand, wenn sie noch nicht existiert' {
        $seedPath = Join-Path $TestDrive "seed-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared-$(New-Guid)/project-routes.txt"
        Set-Content -Path $seedPath -Value @('praefix=Java', 'suffix=Arrays')

        Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath

        Test-Path $targetPath | Should -BeTrue
        Get-Content -Path $targetPath | Should -Be @('praefix=Java', 'suffix=Arrays')
    }

    It 'ergänzt nur die im Ziel fehlenden Zeilen aus dem Startbestand, ohne dort bereits vorhandene (z. B. automatisch registrierte) Zeilen anzutasten' {
        $seedPath = Join-Path $TestDrive "seed2-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared2-$(New-Guid).txt"
        Set-Content -Path $seedPath -Value @('praefix=Java', 'suffix=Arrays', 'praefix=Python')
        Set-Content -Path $targetPath -Value @('praefix=Java', 'suffix=Arrays', 'suffix=NurAmZiel')

        Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath

        $lines = Get-Content -Path $targetPath
        $lines | Should -Contain 'praefix=Python'
        $lines | Should -Contain 'suffix=NurAmZiel'
        ($lines | Where-Object { $_ -eq 'praefix=Java' }).Count | Should -Be 1
    }

    It 'klebt neue Zeilen nicht an die letzte Zeile, wenn die Ziel-Whitelist ohne abschließenden Zeilenumbruch endet' {
        $seedPath = Join-Path $TestDrive "seed4-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared4-$(New-Guid).txt"
        Set-Content -Path $seedPath -Value @('praefix=Zahlensysteme', 'suffix=Hexadezimal')
        Set-Content -Path $targetPath -Value "praefix=PowerShell`r`nsuffix=Registry" -NoNewline

        Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath

        $lines = Get-Content -Path $targetPath
        $lines | Should -Contain 'suffix=Registry'
        $lines | Should -Contain 'praefix=Zahlensysteme'
        $registry = Get-PraefixSuffixRegistry -Path $targetPath
        $registry.Suffixe.Contains('Registry') | Should -BeTrue
    }

    It 'repariert bereits zusammengeklebte Zeilen in der Ziel-Whitelist' {
        $seedPath = Join-Path $TestDrive "seed5-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared5-$(New-Guid).txt"
        Set-Content -Path $seedPath -Value @('suffix=Arrays')
        Set-Content -Path $targetPath -Value @('praefix=PowerShell', 'suffix=Registrysuffix=Arrays')

        Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath

        $lines = Get-Content -Path $targetPath
        $lines | Should -Contain 'suffix=Registry'
        ($lines | Where-Object { $_ -eq 'suffix=Arrays' }).Count | Should -Be 1
    }

    It 'wirft nicht, wenn die Ziel-Whitelist leer ist' {
        $seedPath = Join-Path $TestDrive "seed6-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared6-$(New-Guid).txt"
        Set-Content -Path $seedPath -Value @('praefix=Java')
        New-Item -Path $targetPath -ItemType File -Force | Out-Null

        { Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath } | Should -Not -Throw
        Get-Content -Path $targetPath | Should -Contain 'praefix=Java'
    }

    It 'macht nichts, wenn der Startbestand nicht existiert' {
        $seedPath = Join-Path $TestDrive "missing-seed-$(New-Guid).txt"
        $targetPath = Join-Path $TestDrive "shared3-$(New-Guid).txt"
        Set-Content -Path $targetPath -Value @('praefix=Java')

        { Sync-ProjectRoutesFromSeed -SeedPath $seedPath -TargetPath $targetPath } | Should -Not -Throw
        Get-Content -Path $targetPath | Should -Be @('praefix=Java')
    }
}

Describe 'Copy-NewFiles: relativer Dedup-Key und Ziel-Existenz-Check' {
    BeforeEach {
        $script:sourceDir = Join-Path $TestDrive "quelle-$(New-Guid)"
        $script:targetDir = Join-Path $TestDrive "ziel-$(New-Guid)"
        New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:targetDir -ItemType Directory -Force | Out-Null

        $script:rules = @(
            @{
                match  = '^(?<name>.+)$'
                rename = '{name}'
            }
        )
        $script:sources = @(@{ path = $script:sourceDir; recursive = $false; includePatterns = @('*.pdf'); excludePatterns = @() })
        $script:targets = @(@{ path = $script:targetDir; preserveSubfolders = $false })
    }

    It 'baut den Dedup-Key aus dem konfigurierten (ggf. wildcardhaltigen) source.path statt dem aufgelösten Rechnerpfad (Multi-Machine-Fix)' {
        $marker = "wc-$(New-Guid)"
        $realDir = Join-Path $TestDrive $marker
        New-Item -Path $realDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $realDir 'a.pdf') -Value 'dummy'

        $wildcardPattern = Join-Path $TestDrive "$marker*"
        $wildcardSources = @(@{ path = $wildcardPattern; recursive = $false; includePatterns = @('*.pdf'); excludePatterns = @() })
        $state = @{ processed = @{}; reviewedFiles = @{} }

        Copy-NewFiles -Sources $wildcardSources -Targets $script:targets -State $state -Rules $script:rules -DefaultNameFormat '{originalName}'

        $key = ($state.processed.Keys | Select-Object -First 1)
        $key | Should -Not -BeNullOrEmpty
        $key | Should -Match ([regex]::Escape($wildcardPattern.ToLowerInvariant()))
        $key | Should -Match 'a\.pdf$'
    }

    It 'kopiert eine bereits vorhandene Zieldatei nicht erneut (Ziel-Existenz-Check)' {
        Set-Content -Path (Join-Path $script:sourceDir 'a.pdf') -Value 'quelle'
        Set-Content -Path (Join-Path $script:targetDir 'a.pdf') -Value 'bereits vorhanden'
        $state = @{ processed = @{}; reviewedFiles = @{} }

        Copy-NewFiles -Sources $script:sources -Targets $script:targets -State $state -Rules $script:rules -DefaultNameFormat '{originalName}'

        Get-Content -Path (Join-Path $script:targetDir 'a.pdf') -Raw | Should -Match 'bereits vorhanden'
    }

    It 'überspringt Dateien im konfigurierten Korrigiert-Unterordner der Quelle' {
        $korrigiertDir = Join-Path $script:sourceDir 'Korrigiert'
        New-Item -Path $korrigiertDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $korrigiertDir 'zurueckkopiert.pdf') -Value 'dummy'
        $recursiveSources = @(@{ path = $script:sourceDir; recursive = $true; includePatterns = @('*.pdf'); excludePatterns = @() })
        $state = @{ processed = @{}; reviewedFiles = @{} }

        Copy-NewFiles -Sources $recursiveSources -Targets $script:targets -State $state -Rules $script:rules -DefaultNameFormat '{originalName}' -KorrigiertFolderName 'Korrigiert'

        Test-Path (Join-Path $script:targetDir 'zurueckkopiert.pdf') | Should -BeFalse
    }
}

Describe 'Test-DocFlowPraefixSuffixKnown' {
    BeforeAll {
        $script:registry = [ordered]@{
            Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Suffixe  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        [void]$script:registry.Praefixe.Add('Java')
        [void]$script:registry.Suffixe.Add('Arrays')
    }

    It 'gibt true zurück, wenn Präfix UND Suffix bereits bekannt sind' {
        Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Java' -Suffix 'Arrays' | Should -BeTrue
    }

    It 'gibt false zurück, wenn nur der Präfix bekannt ist' {
        Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Java' -Suffix 'Unbekannt' | Should -BeFalse
    }

    It 'gibt false zurück, wenn nur der Suffix bekannt ist' {
        Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Unbekannt' -Suffix 'Arrays' | Should -BeFalse
    }
}

Describe 'Copy-NewFiles: Praefix/Suffix-Whitelist bei aufgabenRoot' {
    BeforeEach {
        $script:sourceDir2 = Join-Path $TestDrive "quelle2-$(New-Guid)"
        $script:aufgabenRoot2 = Join-Path $TestDrive "aufgaben2-$(New-Guid)"
        New-Item -Path $script:sourceDir2 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:aufgabenRoot2 -ItemType Directory -Force | Out-Null

        $script:aufgabenRules = @(
            @{
                match  = '^(?<initials>[A-Za-z]+)_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
                rename = '{initials}_{praefix}_{suffix}_{aufgabennummer}'
            }
        )
        $script:aufgabenSources = @(@{ path = $script:sourceDir2; recursive = $false; includePatterns = @('*.pdf'); excludePatterns = @() })
        $script:aufgabenTargets = @(@{ path = (Join-Path $TestDrive "archiv2-$(New-Guid)"); preserveSubfolders = $false })
        $script:hintConfig = @{ enabled = $true; fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'; message = 'Fehler: Praefix={praefix} Suffix={suffix}' }

        $script:knownRegistry = [ordered]@{
            Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Suffixe  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        [void]$script:knownRegistry.Praefixe.Add('Java')
        [void]$script:knownRegistry.Suffixe.Add('Arrays')
    }

    It 'routet eine Datei mit bereits bekanntem Praefix/Suffix nach aufgabenRoot' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Java_Arrays_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $registryPath = Join-Path $TestDrive "registry-$(New-Guid).txt"

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $script:knownRegistry -RegistryFilePath $registryPath -NamingConventionHint $script:hintConfig

        Test-Path (Join-Path (Join-Path $script:aufgabenRoot2 'Java') 'Arrays/pke_Java_Arrays_abc.pdf') | Should -BeTrue
    }

    It 'kopiert eine Datei mit unbekanntem Praefix/Suffix NICHT und erzeugt stattdessen einen Hinweis (keine automatische Aufnahme in die Registry)' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Ruby_Basics_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $registryPath = Join-Path $TestDrive "registry-$(New-Guid).txt"

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $script:knownRegistry -RegistryFilePath $registryPath -NamingConventionHint $script:hintConfig

        Test-Path (Join-Path $script:aufgabenRoot2 'Ruby') | Should -BeFalse
        Test-Path (Join-Path $script:sourceDir2 'pke_Ruby_Basics_abc.pdf.NAMENSKONVENTION-FEHLER.txt') | Should -BeTrue
        $script:knownRegistry.Praefixe.Contains('Ruby') | Should -BeFalse
        (Test-Path $registryPath) | Should -BeFalse
    }

    It 'akzeptiert jeden gültig geformten Praefix/Suffix, wenn gar keine Registry konfiguriert ist (RegistryFilePath = $null)' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Ruby_Basics_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $emptyRegistry = [ordered]@{
            Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Suffixe  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $emptyRegistry -RegistryFilePath $null -NamingConventionHint $script:hintConfig

        Test-Path (Join-Path (Join-Path $script:aufgabenRoot2 'Ruby') 'Basics/pke_Ruby_Basics_abc.pdf') | Should -BeTrue
    }

    It 'nennt im Log unbekanntes Praefix und Suffix, wenn die Registry keine Paare enthält' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Ruby_Basics_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $registryPath = Join-Path $TestDrive "registry-$(New-Guid).txt"
        Mock Write-Log -ModuleName DocFlowEngine

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $script:knownRegistry -RegistryFilePath $registryPath -NamingConventionHint $script:hintConfig

        Should -Invoke Write-Log -ModuleName DocFlowEngine -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -eq "Datei 'pke_Ruby_Basics_abc.pdf': Präfix 'Ruby' und Suffix 'Basics' nicht in der Whitelist '$registryPath' eingetragen."
        }
    }

    It 'nennt im Log nur das unbekannte Suffix, wenn das Praefix in der Registry bekannt ist' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Java_Basics_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $registryPath = Join-Path $TestDrive "registry-$(New-Guid).txt"
        Mock Write-Log -ModuleName DocFlowEngine

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $script:knownRegistry -RegistryFilePath $registryPath -NamingConventionHint $script:hintConfig

        Should -Invoke Write-Log -ModuleName DocFlowEngine -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -eq "Datei 'pke_Java_Basics_abc.pdf': Suffix 'Basics' nicht in der Whitelist '$registryPath' eingetragen."
        }
    }

    It 'unterscheidet bei einer Paar-Registry zwischen unbekanntem Praefix und unbekanntem Suffix' {
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Ruby_Arrays_abc.pdf') -Value 'dummy'
        Set-Content -Path (Join-Path $script:sourceDir2 'pke_Java_Basics_abc.pdf') -Value 'dummy'
        $state = @{ processed = @{}; reviewedFiles = @{} }
        $registryPath = Join-Path $TestDrive "registry-$(New-Guid).txt"
        Set-Content -Path $registryPath -Value @('praefix=Java', 'suffix=Arrays')
        $pairRegistry = Get-PraefixSuffixRegistry -Path $registryPath
        Mock Write-Log -ModuleName DocFlowEngine

        Copy-NewFiles -Sources $script:aufgabenSources -Targets $script:aufgabenTargets -State $state -Rules $script:aufgabenRules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:aufgabenRoot2 -PraefixSuffixRegistry $pairRegistry -RegistryFilePath $registryPath -NamingConventionHint $script:hintConfig

        Should -Invoke Write-Log -ModuleName DocFlowEngine -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Datei 'pke_Ruby_Arrays_abc.pdf': Präfix 'Ruby' ist nicht in der Whitelist '$registryPath' eingetragen."
        }
        Should -Invoke Write-Log -ModuleName DocFlowEngine -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Datei 'pke_Java_Basics_abc.pdf': Suffix 'Basics' ist für Präfix 'Java' nicht in der Whitelist '$registryPath' eingetragen."
        }
    }
}

Describe 'Lock-DocFlowRun / Unlock-DocFlowRun' {
    It 'verweigert einen zweiten Lauf, solange die Lock-Datei frisch ist' {
        $lockPath = Join-Path $TestDrive "lock-$(New-Guid)/.docflow-lock"

        $first = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes 15
        $second = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes 15

        $first | Should -BeTrue
        $second | Should -BeFalse
    }

    It 'übernimmt eine abgelaufene Lock-Datei' {
        $lockPath = Join-Path $TestDrive "lock2-$(New-Guid)/.docflow-lock"

        Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes 15 | Out-Null
        $overridden = Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes 0

        $overridden | Should -BeTrue
    }

    It 'entfernt die Lock-Datei beim Entsperren' {
        $lockPath = Join-Path $TestDrive "lock3-$(New-Guid)/.docflow-lock"
        Lock-DocFlowRun -LockPath $lockPath -TimeoutMinutes 15 | Out-Null

        Unlock-DocFlowRun -LockPath $lockPath

        Test-Path -Path $lockPath -PathType Leaf | Should -BeFalse
    }
}

Describe 'Import-DocFlowConfig: Defaults für neue Optionen' {
    It 'setzt sinnvolle Defaults für reviewMarker, unknownKuerzelHint und namingConventionHint, wenn sie in der Config fehlen' {
        $configPath = Join-Path $TestDrive 'minimal-config.psd1'
        @'
@{
    sources = @(@{ path = "."; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    targets = @(@{ path = "."; createIfMissing = $true; preserveSubfolders = $false })
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        $config = Import-DocFlowConfig -Path $configPath

        $config.reviewMarker.enabled | Should -BeFalse
        $config.reviewMarker.korrigiertFolderName | Should -Be 'Korrigiert'
        $config.namingConventionHint.fileNameSuffix | Should -Be '.NAMENSKONVENTION-FEHLER.txt'
        $config.unknownKuerzelHint.enabled | Should -BeTrue
        $config.lockTimeoutMinutes | Should -Be 15
        $config.stateRetentionYears | Should -Be 3
        $config.defaultNameFormat | Should -Be '{timestamp}_{originalName}'
    }
}

Describe 'Remove-DocFlowExpiredState' {
    It 'entfernt Eintraege, deren processedAt aelter als die Aufbewahrungsfrist ist' {
        $state = @{
            processed = @{
                'alt' = @{ source = '/a'; processedAt = (Get-Date).AddYears(-4).ToString('o') }
                'neu' = @{ source = '/b'; processedAt = (Get-Date).AddMonths(-6).ToString('o') }
            }
            reviewedFiles = @{}
        }

        $removed = Remove-DocFlowExpiredState -State $state -RetentionYears 3

        $removed | Should -Be 1
        $state.processed.ContainsKey('alt') | Should -BeFalse
        $state.processed.ContainsKey('neu') | Should -BeTrue
    }

    It 'entfernt abgelaufene Eintraege auch aus reviewedFiles' {
        $state = @{
            processed = @{}
            reviewedFiles = @{
                'alt' = @{ source = '/a'; processedAt = (Get-Date).AddYears(-5).ToString('o') }
            }
        }

        $removed = Remove-DocFlowExpiredState -State $state -RetentionYears 3

        $removed | Should -Be 1
        $state.reviewedFiles.Count | Should -Be 0
    }

    It 'laesst Eintraege ohne verwertbares processedAt unangetastet' {
        $state = @{
            processed = @{
                'ohne-datum' = @{ source = '/a' }
                'kaputtes-datum' = @{ source = '/b'; processedAt = 'kein-datum' }
            }
            reviewedFiles = @{}
        }

        $removed = Remove-DocFlowExpiredState -State $state -RetentionYears 3

        $removed | Should -Be 0
        $state.processed.Count | Should -Be 2
    }
}

Describe 'Get-DocFlowMigratedFileName' {
    BeforeAll {
        $script:migrationRules = @(
            @{
                match = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            }
        )
        $script:migrationRegistry = [ordered]@{
            Praefixe = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Suffixe  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        [void]$script:migrationRegistry.Praefixe.Add('Java')
        [void]$script:migrationRegistry.Suffixe.Add('Arrays')
    }

    It 'laesst einen bereits regelkonformen Namen unveraendert' {
        Get-DocFlowMigratedFileName -Name 'pke_Java_Arrays_abc' -Rules $script:migrationRules -Registry $script:migrationRegistry | Should -Be 'pke_Java_Arrays_abc'
    }

    It 'erkennt bekannten Praefix und Suffix aus der Whitelist und Initialen am Anfang, Aufgabennummer am Ende' {
        $result = Get-DocFlowMigratedFileName -Name 'pke Java Arrays Blatt3' -Rules $script:migrationRules -Registry $script:migrationRegistry
        $result | Should -Be 'pke_Java_Arrays_Blatt3'
    }

    It 'setzt Platzhalter fuer Teile, die sich nicht bestimmen lassen' {
        $result = Get-DocFlowMigratedFileName -Name 'irgendwas komplett anderes' -Rules $script:migrationRules -Registry $script:migrationRegistry -Placeholder 'PLATZHALTER'
        $result | Should -Match 'PLATZHALTER'
    }

    It 'nutzt ueberall Platzhalter, wenn keine Registry uebergeben wird' {
        $result = Get-DocFlowMigratedFileName -Name 'pke Java Arrays Blatt3' -Rules $script:migrationRules -Registry $null
        $result | Should -Be 'pke_PLATZHALTER_PLATZHALTER_Blatt3'
    }
}

Describe 'Import-DocFlowConfig: Pfad-Variablen aus paths' {
    It 'setzt die Werte aus paths in alle Pfadfelder ein, auch verschachtelt' {
        $configPath = Join-Path $TestDrive "paths-config-$(New-Guid).psd1"
        @'
@{
    paths = @{
        basis  = 'C:/Basis'
        shared = '{basis}/Shared'
    }
    sources = @(@{ path = "{basis}/Quelle/"; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    targets = @(@{ path = "{basis}/Archiv"; createIfMissing = $true; preserveSubfolders = $false })
    aufgabenRoot = '{basis}/Aufgaben'
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{timestamp}_{name}" })
    reviewMarker = @{ enabled = $true; kuerzelRoutesFile = '{shared}/kuerzel-routes.txt' }
    projectRoutesFile = '{shared}/project-routes.txt'
    stateFile = '{shared}/state.json'
    lockFile = '{shared}/.lock'
    log = @{ level = 'Info'; file = '{shared}/docflow.log' }
}
'@ | Set-Content -Path $configPath

        $config = Import-DocFlowConfig -Path $configPath

        $config.sources[0].path | Should -Be 'C:/Basis/Quelle/'
        $config.targets[0].path | Should -Be 'C:/Basis/Archiv'
        $config.aufgabenRoot | Should -Be 'C:/Basis/Aufgaben'
        $config.reviewMarker.kuerzelRoutesFile | Should -Be 'C:/Basis/Shared/kuerzel-routes.txt'
        $config.projectRoutesFile | Should -Be 'C:/Basis/Shared/project-routes.txt'
        $config.stateFile | Should -Be 'C:/Basis/Shared/state.json'
        $config.lockFile | Should -Be 'C:/Basis/Shared/.lock'
        $config.log.file | Should -Be 'C:/Basis/Shared/docflow.log'
        $config.namingConventions[0].rename | Should -Be '{timestamp}_{name}'
    }

    It 'wirft bei einer nicht definierten Pfad-Variable' {
        $configPath = Join-Path $TestDrive "paths-config-$(New-Guid).psd1"
        @'
@{
    paths = @{ basis = 'C:/Basis' }
    sources = @(@{ path = "{gibtsnicht}/Quelle"; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    targets = @(@{ path = "{basis}/Archiv"; createIfMissing = $true; preserveSubfolders = $false })
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        { Import-DocFlowConfig -Path $configPath } | Should -Throw '*gibtsnicht*'
    }

    It 'wirft bei einem zirkulären Verweis in paths' {
        $configPath = Join-Path $TestDrive "paths-config-$(New-Guid).psd1"
        @'
@{
    paths = @{ a = '{b}/x'; b = '{a}/y' }
    sources = @(@{ path = "{a}"; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    targets = @(@{ path = "."; createIfMissing = $true; preserveSubfolders = $false })
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        { Import-DocFlowConfig -Path $configPath } | Should -Throw '*Zirkulär*'
    }
}

Describe 'Betrieb ohne targets (kein Archiv)' {
    It 'akzeptiert eine Konfiguration ohne targets, wenn aufgabenRoot gesetzt ist' {
        $configPath = Join-Path $TestDrive "no-targets-$(New-Guid).psd1"
        @'
@{
    sources = @(@{ path = "."; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    aufgabenRoot = './Aufgaben'
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        $config = Import-DocFlowConfig -Path $configPath
        @($config.targets).Count | Should -Be 0
    }

    It 'wirft, wenn weder targets noch aufgabenRoot gesetzt sind' {
        $configPath = Join-Path $TestDrive "no-targets-$(New-Guid).psd1"
        @'
@{
    sources = @(@{ path = "."; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        { Import-DocFlowConfig -Path $configPath } | Should -Throw '*aufgabenRoot*'
    }

    It 'überspringt eine nicht routbare Datei ohne Archiv-Kopie und ohne Zustandseintrag' {
        $sourceDir = Join-Path $TestDrive "quelle-nt-$(New-Guid)"
        $aufgabenRoot = Join-Path $TestDrive "aufgaben-nt-$(New-Guid)"
        New-Item -Path $sourceDir, $aufgabenRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $sourceDir 'falsch benannt.pdf') -Value 'dummy'
        $rules = @(@{ match = '^(?<initials>[A-Za-z]+)_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'; rename = '{initials}_{praefix}_{suffix}_{aufgabennummer}' })
        $sources = @(@{ path = $sourceDir; recursive = $false; includePatterns = @('*.pdf'); excludePatterns = @() })
        $state = @{ processed = @{}; reviewedFiles = @{} }

        Copy-NewFiles -Sources $sources -Targets @() -State $state -Rules $rules -DefaultNameFormat '{originalName}' -AufgabenRoot $aufgabenRoot -NamingConventionHint @{ enabled = $false }

        $state.processed.Count | Should -Be 0
        @(Get-ChildItem -Path $aufgabenRoot -Recurse -File).Count | Should -Be 0
    }
}

Describe 'Abgabe-Absicherung (Kopierwiederholung, Doppelabgabe, Schreibschutz, Paar-Whitelist, Hinweis-Aufräumen)' {
    BeforeEach {
        $script:src = Join-Path $TestDrive "abg-src-$(New-Guid)"
        $script:auf = Join-Path $TestDrive "abg-auf-$(New-Guid)"
        New-Item -Path $script:src, $script:auf -ItemType Directory -Force | Out-Null
        $script:rules = @(
            @{
                match  = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
                rename = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
            }
        )
        $script:sources = @(@{ path = $script:src; recursive = $false; includePatterns = @('*.pdf'); excludePatterns = @('*.NAMENSKONVENTION-FEHLER.txt', '*.BEREITS-ABGEGEBEN.txt') })
        $script:namingHint = @{ enabled = $true; fileNameSuffix = '.NAMENSKONVENTION-FEHLER.txt'; message = 'Name falsch: {fileName}' }
        $script:dupHint = @{ enabled = $true; fileNameSuffix = '.BEREITS-ABGEGEBEN.txt'; message = '{fileName} gibt es schon, bitte {suggestedName}' }
        $script:registryPath = Join-Path $TestDrive "abg-reg-$(New-Guid).txt"
        Set-Content -Path $script:registryPath -Value @('praefix=Java', 'suffix=Arrays', 'praefix=Zahlensysteme', 'suffix=Hexadezimal')
        $script:registry = Get-PraefixSuffixRegistry -Path $script:registryPath
        $script:state = @{ processed = @{}; reviewedFiles = @{} }
        $script:run = {
            param([double]$MinAge = 0)
            Copy-NewFiles -Sources $script:sources -Targets @() -State $script:state -Rules $script:rules -DefaultNameFormat '{originalName}' -AufgabenRoot $script:auf -PraefixSuffixRegistry $script:registry -RegistryFilePath $script:registryPath -NamingConventionHint $script:namingHint -DuplicateHint $script:dupHint -MinFileAgeMinutes $MinAge -RetryCount 2 -RetryDelaySeconds 0
        }
        $script:arraysDir = Join-Path (Join-Path $script:auf 'Java') 'Arrays'
    }

    Context 'Kopieren mit Wiederholung' {
        It 'versucht es insgesamt dreimal und gibt bei Erfolg im dritten Versuch true zurück' {
            $global:docflowCopyCalls = 0
            Mock Copy-Item -ModuleName DocFlowEngine -MockWith {
                $global:docflowCopyCalls++
                if ($global:docflowCopyCalls -lt 3) { throw 'gesperrt' }
                [System.IO.File]::Copy($LiteralPath, $Destination, $true)
            }
            $sourceFile = Join-Path $script:src 'a.pdf'
            Set-Content -Path $sourceFile -Value 'inhalt'

            Copy-DocFlowFileWithRetry -Source $sourceFile -Destination (Join-Path $script:auf 'a.pdf') -RetryCount 2 -RetryDelaySeconds 0 | Should -BeTrue
            $global:docflowCopyCalls | Should -Be 3
        }

        It 'trägt eine Datei nicht als verarbeitet ein, wenn alle drei Versuche scheitern, und kopiert sie im nächsten Lauf' {
            Mock Copy-Item -ModuleName DocFlowEngine -MockWith { throw 'gesperrt' }
            Set-Content -Path (Join-Path $script:src 'ahf_Java_Arrays_1.pdf') -Value 'inhalt'

            & $script:run
            Should -Invoke Copy-Item -ModuleName DocFlowEngine -Times 3 -Exactly
            $script:state.processed.Count | Should -Be 0

            Mock Copy-Item -ModuleName DocFlowEngine -MockWith { [System.IO.File]::Copy($LiteralPath, $Destination, $true) }
            & $script:run
            $script:state.processed.Count | Should -Be 1
            @(Get-ChildItem -Path $script:arraysDir -File).Count | Should -Be 1
        }
    }

    Context 'Bereits abgegeben' {
        It 'kopiert eine nach der Abgabe überschriebene Datei nicht erneut und schlägt _v2_ vor' {
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'erste Fassung'
            & $script:run
            Set-Content -Path $file -Value 'zweite, deutlich längere Fassung'

            & $script:run

            @(Get-ChildItem -Path $script:arraysDir -File).Count | Should -Be 1
            $hint = "$file.BEREITS-ABGEGEBEN.txt"
            Test-Path $hint | Should -BeTrue
            Get-Content -Path $hint -Raw | Should -Match 'ahf_v2_Java_Arrays_1\.pdf'
        }

        It 'erkennt eine gleichnamige Abgabe im Aufgaben-Ordner und schlägt die nächste freie Version vor' {
            New-Item -Path $script:arraysDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $script:arraysDir '20260101_ahf_Java_Arrays_1.pdf') -Value 'alte Abgabe mit anderer Länge'
            Set-Content -Path (Join-Path $script:arraysDir '20260102_ahf_v2_Java_Arrays_1.pdf') -Value 'v2'
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'neu'

            & $script:run

            $script:state.processed.Count | Should -Be 0
            Get-Content -Path "$file.BEREITS-ABGEGEBEN.txt" -Raw | Should -Match 'ahf_v3_Java_Arrays_1\.pdf'
        }

        It 'übernimmt eine identische, bereits vorhandene Zieldatei ohne Hinweis (z. B. nach abgebrochenem Lauf)' {
            New-Item -Path $script:arraysDir -ItemType Directory -Force | Out-Null
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'gleich'
            Copy-Item -Path $file -Destination (Join-Path $script:arraysDir '20260101_ahf_Java_Arrays_1.pdf')

            & $script:run

            $script:state.processed.Count | Should -Be 1
            Test-Path "$file.BEREITS-ABGEGEBEN.txt" | Should -BeFalse
        }

        It 'kopiert eine Abgabe mit _v2_ normal neben die erste' {
            Set-Content -Path (Join-Path $script:src 'ahf_Java_Arrays_1.pdf') -Value 'v1'
            & $script:run
            Set-Content -Path (Join-Path $script:src 'ahf_v2_Java_Arrays_1.pdf') -Value 'v2'
            & $script:run

            @(Get-ChildItem -Path $script:arraysDir -File).Count | Should -Be 2
        }

        It 'trägt bei alten Zustandseinträgen ohne Größe/Zeit nur die Werte nach, ohne zu kopieren oder zu warnen' {
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'alt'
            $key = ("$($script:src)|ahf_Java_Arrays_1.pdf").ToLowerInvariant()
            $script:state.processed[$key] = @{ source = $file; targets = @(); processedAt = (Get-Date).ToString('o') }

            & $script:run

            $script:state.processed[$key]['length'] | Should -BeGreaterThan 0
            Test-Path $script:arraysDir | Should -BeFalse
            Test-Path "$file.BEREITS-ABGEGEBEN.txt" | Should -BeFalse
        }
    }

    Context 'Dateien, die noch geschrieben werden' {
        It 'verarbeitet eine zu frisch geänderte Datei erst später' {
            Set-Content -Path (Join-Path $script:src 'ahf_Java_Arrays_1.pdf') -Value 'frisch'

            & $script:run 5

            $script:state.processed.Count | Should -Be 0
            Test-Path $script:arraysDir | Should -BeFalse
        }

        It 'akzeptiert eine Datei, die älter als die Mindestwartezeit ist' {
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'alt genug'
            (Get-Item $file).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-10)

            & $script:run 5

            $script:state.processed.Count | Should -Be 1
        }

        It 'verarbeitet eine gesperrte Datei nicht' {
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'gesperrt'
            $lock = [System.IO.File]::Open($file, 'Open', 'ReadWrite', 'None')
            try {
                Test-DocFlowFileReady -File (Get-Item $file) | Should -BeFalse
            } finally {
                $lock.Dispose()
            }
            Test-DocFlowFileReady -File (Get-Item $file) | Should -BeTrue
        }
    }

    Context 'Groß-/Kleinschreibung' {
        It 'behandelt _V2_ wie _v2_ (Zielname mit Datum, Kürzel erkennbar)' {
            $file = New-Item -Path (Join-Path $script:src 'AHf_V2_Java_Arrays_1.pdf') -ItemType File -Force
            Get-TargetFileName -File $file -Rules $script:rules -DefaultFormat '{timestamp}_{originalName}' | Should -Match '^\d{8}_AHf_V2_Java_Arrays_1\.pdf$'
            Get-FileInitialsFromName -Name '20260101_AHf_V2_Java_Arrays_1' -Rules $script:rules | Should -BeNullOrEmpty
            Get-FileInitialsFromName -Name 'AHf_V2_Java_Arrays_1' -Rules $script:rules | Should -Be 'AHf'
        }

        It 'erkennt eine Korrektur-Markierung mit großem K' {
            $studentDir = Join-Path $TestDrive "student-$(New-Guid)"
            New-Item -Path $studentDir, $script:arraysDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $script:arraysDir '20260101_ahf_Java_Arrays_1_K-AHF.pdf') -Value 'korrigiert'

            Copy-ReviewedFiles -AufgabenRoot $script:auf -ReviewMarker @{ enabled = $true; pattern = '_k-[A-Za-z0-9]+$'; korrigiertFolderName = 'Korrigiert' } -KuerzelRoutes @{ ahf = $studentDir } -State $script:state -Rules $script:rules -RetryDelaySeconds 0

            Test-Path (Join-Path $studentDir 'Korrigiert/20260101_ahf_Java_Arrays_1_K-AHF.pdf') | Should -BeTrue
        }
    }

    Context 'Präfix/Suffix als Paar' {
        It 'lehnt eine Kombination ab, deren Suffix nur unter einem anderen Präfix steht' {
            Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Java' -Suffix 'Arrays' | Should -BeTrue
            Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'java' -Suffix 'ARRAYS' | Should -BeTrue
            Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Java' -Suffix 'Hexadezimal' | Should -BeFalse
            Test-DocFlowPraefixSuffixKnown -Registry $script:registry -Praefix 'Zahlensysteme' -Suffix 'Arrays' | Should -BeFalse
        }

        It 'erlaubt denselben Suffix unter mehreren Präfixen' {
            Set-Content -Path $script:registryPath -Value @('praefix=Java', 'suffix=Einfuehrung', 'praefix=Python', 'suffix=Einfuehrung')
            $registry = Get-PraefixSuffixRegistry -Path $script:registryPath
            Test-DocFlowPraefixSuffixKnown -Registry $registry -Praefix 'Python' -Suffix 'Einfuehrung' | Should -BeTrue
        }

        It 'kopiert Zahlensysteme_Arrays nicht und erzeugt einen Namenshinweis' {
            Set-Content -Path (Join-Path $script:src 'ahf_Zahlensysteme_Arrays_1.pdf') -Value 'x'

            & $script:run

            $script:state.processed.Count | Should -Be 0
            Test-Path (Join-Path $script:src 'ahf_Zahlensysteme_Arrays_1.pdf.NAMENSKONVENTION-FEHLER.txt') | Should -BeTrue
        }

        It 'ordnet beim Abgleich neue Suffixe dem richtigen Präfix zu statt sie anzuhängen' {
            $seed = Join-Path $TestDrive "abg-seed-$(New-Guid).txt"
            $target = Join-Path $TestDrive "abg-target-$(New-Guid).txt"
            Set-Content -Path $seed -Value @('praefix=Java', 'suffix=Arrays', 'suffix=ArrayList', 'praefix=Zahlensysteme', 'suffix=Binaer')
            Set-Content -Path $target -Value @('praefix=Java', 'suffix=Arrays', 'praefix=PowerShell', 'suffix=Registry')

            Sync-ProjectRoutesFromSeed -SeedPath $seed -TargetPath $target

            Get-Content -Path $target | Should -Be @('praefix=Java', 'suffix=Arrays', 'suffix=ArrayList', 'praefix=PowerShell', 'suffix=Registry', 'praefix=Zahlensysteme', 'suffix=Binaer')
            $registry = Get-PraefixSuffixRegistry -Path $target
            Test-DocFlowPraefixSuffixKnown -Registry $registry -Praefix 'Java' -Suffix 'ArrayList' | Should -BeTrue
            Test-DocFlowPraefixSuffixKnown -Registry $registry -Praefix 'PowerShell' -Suffix 'ArrayList' | Should -BeFalse
        }

        It 'lässt eine bereits passende Whitelist unverändert (inkl. Kommentaren)' {
            $seed = Join-Path $TestDrive "abg-seed2-$(New-Guid).txt"
            $target = Join-Path $TestDrive "abg-target2-$(New-Guid).txt"
            Set-Content -Path $seed -Value @('praefix=Java', 'suffix=Arrays')
            Set-Content -Path $target -Value @('# eigener Kommentar', 'praefix=Java', 'suffix=Arrays')

            Sync-ProjectRoutesFromSeed -SeedPath $seed -TargetPath $target

            (Get-Content -Path $target)[0] | Should -Be '# eigener Kommentar'
        }
    }

    Context 'Hinweisdateien aufräumen' {
        It 'entfernt einen Namenshinweis, wenn die Datei umbenannt wurde' {
            $hint = Join-Path $script:src 'ahf_Java_1.pdf.NAMENSKONVENTION-FEHLER.txt'
            Set-Content -Path $hint -Value 'alt'
            Set-Content -Path (Join-Path $script:src 'ahf_Java_Arrays_1.pdf') -Value 'umbenannt'

            & $script:run

            Test-Path $hint | Should -BeFalse
            $script:state.processed.Count | Should -Be 1
        }

        It 'entfernt einen Hinweis zur Datei, sobald sie erfolgreich kopiert wurde' {
            $file = Join-Path $script:src 'ahf_Java_Arrays_1.pdf'
            Set-Content -Path $file -Value 'x'
            Set-Content -Path "$file.NAMENSKONVENTION-FEHLER.txt" -Value 'alt'

            & $script:run

            Test-Path "$file.NAMENSKONVENTION-FEHLER.txt" | Should -BeFalse
        }

        It 'behält einen Hinweis, solange die betroffene Datei unverändert falsch ist' {
            $file = Join-Path $script:src 'ahf_Java_1.pdf'
            Set-Content -Path $file -Value 'x'

            & $script:run
            & $script:run

            Test-Path "$file.NAMENSKONVENTION-FEHLER.txt" | Should -BeTrue
        }

        It 'entfernt einen KUERZEL-UNBEKANNT-Hinweis, sobald die Korrektur zurückkopiert werden konnte' {
            $studentDir = Join-Path $TestDrive "student2-$(New-Guid)"
            New-Item -Path $studentDir, $script:arraysDir -ItemType Directory -Force | Out-Null
            $korrektur = Join-Path $script:arraysDir '20260101_ahf_Java_Arrays_1_k-ahf.pdf'
            Set-Content -Path $korrektur -Value 'korrigiert'
            Set-Content -Path "$korrektur.KUERZEL-UNBEKANNT.txt" -Value 'alt'

            Copy-ReviewedFiles -AufgabenRoot $script:auf -ReviewMarker @{ enabled = $true; pattern = '_k-[A-Za-z0-9]+$'; korrigiertFolderName = 'Korrigiert' } -KuerzelRoutes @{ ahf = $studentDir } -State $script:state -Rules $script:rules -RetryDelaySeconds 0

            Test-Path "$korrektur.KUERZEL-UNBEKANNT.txt" | Should -BeFalse
        }
    }
}

Describe 'Rename-ExistingAufgaben.ps1' {
    BeforeEach {
        $script:renameScript = Join-Path $PSScriptRoot '../scripts/Rename-ExistingAufgaben.ps1'
        $script:renameRoot = Join-Path $TestDrive "rename-$(New-Guid)"
        $script:renameStudent = Join-Path $script:renameRoot 'quelle/pke'
        New-Item -Path $script:renameStudent -ItemType Directory -Force | Out-Null

        $registryPath = Join-Path $script:renameRoot 'project-routes.txt'
        Set-Content -Path $registryPath -Value @('praefix=Java', 'suffix=Arrays')

        $script:renameConfig = Join-Path $script:renameRoot 'config.psd1'
        $configText = @"
@{
    sources = @(@{ path = '$($script:renameRoot)/quelle'; recursive = `$true; includePatterns = @('*.pdf'); excludePatterns = @() })
    aufgabenRoot = '$($script:renameRoot)/aufgaben'
    namingConventions = @(
        @{
            match  = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename = '{date}_{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
        }
    )
    projectRoutesFile = '$registryPath'
    stateFile = '$($script:renameRoot)/state.json'
    log = @{ level = 'Error'; file = '' }
}
"@
        Set-Content -Path $script:renameConfig -Value $configText

        foreach ($name in @('pke_Java_Arrays_abc.pdf', 'Java Arrays Blatt3.pdf', 'Java Arrays abc.pdf', 'irgendwas.pdf')) {
            Set-Content -Path (Join-Path $script:renameStudent $name) -Value 'dummy'
        }
        $script:renameReport = Join-Path $script:renameRoot 'report.csv'
    }

    It 'schlägt in der Vorschau Namen vor, ohne Dateien zu verändern' {
        & $script:renameScript -ConfigPath $script:renameConfig -ReportPath $script:renameReport 6>$null

        $rows = @(Import-Csv -LiteralPath $script:renameReport -Delimiter ';')
        $byOld = @{}
        foreach ($row in $rows) { $byOld[$row.Alt] = $row }

        $rows.Count | Should -Be 4
        $byOld['pke_Java_Arrays_abc.pdf'].Status | Should -Be 'bereits regelkonform'
        $byOld['Java Arrays Blatt3.pdf'].Status | Should -Be 'umbenannt'
        $byOld['Java Arrays Blatt3.pdf'].Neu | Should -Be 'pke_Java_Arrays_Blatt3.pdf'
        $byOld['Java Arrays Blatt3.pdf'].Hinweise | Should -Match "^Initialen 'pke' aus regelkonformen Dateien im Ordner"
        $byOld['Java Arrays abc.pdf'].Neu | Should -Be 'pke_v2_Java_Arrays_abc.pdf'
        $byOld['Java Arrays abc.pdf'].Hinweise | Should -Match 'Name war schon vergeben, Version _v2 gesetzt'
        $byOld['irgendwas.pdf'].Status | Should -Be 'unverändert (kein Fach erkannt)'
        @($rows | Where-Object { $_.Ausgefuehrt -ne 'nein' }).Count | Should -Be 0
        Test-Path (Join-Path $script:renameStudent 'Java Arrays Blatt3.pdf') | Should -BeTrue
    }

    It 'benennt mit -Apply um und macht es mit -Undo rückgängig' {
        & $script:renameScript -ConfigPath $script:renameConfig -ReportPath $script:renameReport -Apply 6>$null

        Test-Path (Join-Path $script:renameStudent 'pke_Java_Arrays_Blatt3.pdf') | Should -BeTrue
        Test-Path (Join-Path $script:renameStudent 'pke_v2_Java_Arrays_abc.pdf') | Should -BeTrue
        Test-Path (Join-Path $script:renameStudent 'irgendwas.pdf') | Should -BeTrue
        @(Import-Csv -LiteralPath $script:renameReport -Delimiter ';' | Where-Object { $_.Ausgefuehrt -eq 'ja' }).Count | Should -Be 2

        & $script:renameScript -Undo $script:renameReport 6>$null

        Test-Path (Join-Path $script:renameStudent 'Java Arrays Blatt3.pdf') | Should -BeTrue
        Test-Path (Join-Path $script:renameStudent 'Java Arrays abc.pdf') | Should -BeTrue
        Test-Path (Join-Path $script:renameStudent 'pke_Java_Arrays_Blatt3.pdf') | Should -BeFalse
    }

    It 'trägt umbenannte Dateien mit -MarkAsProcessed als verarbeitet in den Zustand ein' {
        & $script:renameScript -ConfigPath $script:renameConfig -ReportPath $script:renameReport -Apply -MarkAsProcessed 6>$null

        $state = Get-Content -Path (Join-Path $script:renameRoot 'state.json') -Raw | ConvertFrom-Json
        $keys = @($state.processed.PSObject.Properties.Name)
        $keys.Count | Should -Be 2
        $entry = $state.processed.PSObject.Properties | Where-Object { $_.Name -like '*pke_java_arrays_blatt3.pdf' } | Select-Object -ExpandProperty Value
        $entry.migriert | Should -BeTrue
        @($entry.targets).Count | Should -Be 0
    }
}

Describe 'Get-DocFlowSuggestedVersionName' {
    BeforeAll {
        $script:versionRules = @(
            @{
                match  = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
                rename = '{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
            }
        )
    }

    BeforeEach {
        $script:versionSource = Join-Path $TestDrive "src-$(New-Guid)"
        $script:versionTarget = Join-Path $TestDrive "ziel-$(New-Guid)"
        New-Item -Path $script:versionSource, $script:versionTarget -ItemType Directory -Force | Out-Null
        $script:versionFile = New-Item -Path (Join-Path $script:versionSource 'pke_Java_Arrays_abc.pdf') -ItemType File -Force
    }

    It 'zählt korrigierte Versionen mit dem Standard-Korrekturmarker mit' {
        New-Item -Path (Join-Path $script:versionTarget '20260101_pke_v3_Java_Arrays_abc_k-ahf.pdf') -ItemType File -Force | Out-Null

        Get-DocFlowSuggestedVersionName -File $script:versionFile -Rules $script:versionRules -TargetDirectory $script:versionTarget | Should -Be 'pke_v4_Java_Arrays_abc.pdf'
    }

    It 'zählt korrigierte Versionen mit einem konfigurierten Korrekturmarker mit' {
        New-Item -Path (Join-Path $script:versionTarget '20260101_pke_v3_Java_Arrays_abc_korr-ahf.pdf') -ItemType File -Force | Out-Null

        Get-DocFlowSuggestedVersionName -File $script:versionFile -Rules $script:versionRules -TargetDirectory $script:versionTarget -ReviewMarkerPattern '_korr-[A-Za-z0-9]+$' | Should -Be 'pke_v4_Java_Arrays_abc.pdf'
    }
}

Describe 'Import-DocFlowState / Save-State' {
    It 'behält einelementige targets-Listen beim Speichern und erneuten Laden als Liste' {
        $statePath = Join-Path $TestDrive "state-$(New-Guid).json"
        $state = @{ processed = @{ 'a|b.pdf' = [ordered]@{ source = 'b.pdf'; targets = @('ziel/b.pdf'); processedAt = '2026-01-01T00:00:00' } }; reviewedFiles = @{} }

        Save-State -StatePath $statePath -State $state
        $reloaded = Import-DocFlowState -StatePath $statePath
        Save-State -StatePath $statePath -State $reloaded
        $reloadedAgain = Import-DocFlowState -StatePath $statePath

        , $reloadedAgain.processed['a|b.pdf'].targets | Should -BeOfType [array]
        @($reloadedAgain.processed['a|b.pdf'].targets) | Should -Be @('ziel/b.pdf')
        (Get-Content -Path $statePath -Raw) | Should -Match '"targets":\s*\['
    }

    It 'lädt leere targets-Listen als leere Liste' {
        $statePath = Join-Path $TestDrive "state-$(New-Guid).json"
        Set-Content -Path $statePath -Value '{ "processed": { "k": { "targets": [] } }, "reviewedFiles": {} }'

        $reloaded = Import-DocFlowState -StatePath $statePath

        , $reloaded.processed['k'].targets | Should -BeOfType [array]
        @($reloaded.processed['k'].targets).Count | Should -Be 0
    }
}

Describe 'Copy-NewFiles: Dateinamen mit eckigen Klammern' {
    It 'kopiert Dateien und Unterordner mit [ ] im Namen wörtlich statt als Wildcard' {
        $sourceDir = Join-Path $TestDrive "quelle-$(New-Guid)"
        $studentDir = Join-Path $sourceDir 'Klasse [A]'
        $targetDir = Join-Path $TestDrive "ziel-$(New-Guid)"
        New-Item -Path $studentDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $studentDir 'Bericht [1].pdf') -Value 'dummy'
        $sources = @(@{ path = $sourceDir; recursive = $true; includePatterns = @('*.pdf'); excludePatterns = @() })
        $targets = @(@{ path = $targetDir; preserveSubfolders = $true })
        $rules = @(@{ match = '^(?<name>.+)$'; rename = '{name}' })
        $state = @{ processed = @{}; reviewedFiles = @{} }

        Copy-NewFiles -Sources $sources -Targets $targets -State $state -Rules $rules -DefaultNameFormat '{originalName}' -RetryCount 0 -RetryDelaySeconds 0

        Test-Path -LiteralPath (Join-Path (Join-Path $targetDir 'Klasse [A]') 'Bericht [1].pdf') | Should -BeTrue
        $state.processed.Count | Should -Be 1
    }
}

Describe 'Modul-Exporte' {
    It 'stellt die früheren Funktionsnamen als Aliase bereit' -ForEach @(
        @{ Alias = 'Load-Config'; Target = 'Import-DocFlowConfig' }
        @{ Alias = 'Load-State'; Target = 'Import-DocFlowState' }
        @{ Alias = 'Ensure-TargetDirectories'; Target = 'Initialize-DocFlowTargetDirectories' }
    ) {
        (Get-Command -Name $Alias).ResolvedCommand.Name | Should -Be $Target
    }

    It 'exportiert die Aliase auch beim Import über das Modulmanifest' {
        $manifest = Join-Path $PSScriptRoot '../scripts/DocFlowEngine.psd1'
        $aliases = & (Get-Process -Id $PID).Path -NoProfile -Command "Import-Module '$manifest' -WarningAction SilentlyContinue; (Get-Module DocFlowEngine).ExportedAliases.Keys -join ','"
        ($aliases -split ',' | Sort-Object) | Should -Be @('Ensure-TargetDirectories', 'Load-Config', 'Load-State')
    }
}

Describe 'New-DocFlowSubmissionStem' {
    It 'lässt die Versionsangabe bei Version 0 weg' {
        New-DocFlowSubmissionStem -Initials 'pke' -Praefix 'Java' -Suffix 'Arrays' -Aufgabennummer 'abc' | Should -Be 'pke_Java_Arrays_abc'
    }

    It 'setzt die Versionsangabe hinter die Initialen' {
        New-DocFlowSubmissionStem -Initials 'pke' -Version 3 -Praefix 'Java' -Suffix 'Arrays' -Aufgabennummer 'abc' | Should -Be 'pke_v3_Java_Arrays_abc'
    }
}

Describe 'Resolve-PathOrAbsolute' {
    It 'gibt für einen existierenden Pfad den aufgelösten Pfad zurück' {
        $dir = New-Item -Path (Join-Path $TestDrive "vorhanden-$(New-Guid)") -ItemType Directory -Force
        Resolve-PathOrAbsolute -PathValue $dir.FullName | Should -Be $dir.FullName
    }

    It 'löst Wildcards über das nächste existierende übergeordnete Verzeichnis auf' {
        $base = Join-Path $TestDrive "wild-$(New-Guid)"
        New-Item -Path (Join-Path $base 'Jahrgang-2026') -ItemType Directory -Force | Out-Null
        $expected = Join-Path (Join-Path (Join-Path $base 'Jahrgang-2026') 'neu') 'datei.txt'

        Resolve-PathOrAbsolute -PathValue (Join-Path $base 'Jahrgang-*/neu/datei.txt') | Should -Be $expected
    }

    It 'wirft einen Fehler, wenn für einen relativen Wildcard-Pfad kein übergeordnetes Verzeichnis existiert' {
        Push-Location $TestDrive
        try {
            { Resolve-PathOrAbsolute -PathValue "gibt-es-nicht-$(New-Guid)-*/datei.txt" } | Should -Throw '*Wildcards*'
        } finally {
            Pop-Location
        }
    }

    It 'macht einen nicht existierenden relativen Pfad relativ zum aktuellen Verzeichnis absolut' {
        Push-Location $TestDrive
        try {
            Resolve-PathOrAbsolute -PathValue "neu-$(New-Guid)-x/datei.txt" | Should -BeLike (Join-Path $TestDrive '*-x*datei.txt')
        } finally {
            Pop-Location
        }
    }
}

Describe 'Invoke-OneDriveSync.ps1' {
    It 'beendet sich mit Exit-Code 0 und einer Warnung, wenn OneDrive.exe fehlt' {
        $script = Join-Path $PSScriptRoot '../scripts/Invoke-OneDriveSync.ps1'
        $missing = Join-Path $TestDrive 'gibt-es-nicht/OneDrive.exe'

        $output = & (Get-Process -Id $PID).Path -NoProfile -File $script -ExecutablePath $missing 3>&1 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'OneDrive\.exe wurde nicht gefunden'
    }
}

Describe 'Invoke-DocFlowEngine (Ende-zu-Ende)' {
    BeforeEach {
        $script:e2eRoot = Join-Path $TestDrive "e2e-$(New-Guid)"
        $script:e2eStudent = Join-Path $script:e2eRoot 'quelle/pke'
        $script:e2eShared = Join-Path $script:e2eRoot 'shared'
        $script:e2eAufgaben = Join-Path $script:e2eRoot 'aufgaben'
        New-Item -Path $script:e2eStudent, $script:e2eShared -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $script:e2eShared 'project-routes.txt') -Value @('praefix=Java', 'suffix=Arrays')
        foreach ($name in @('pke_Java_Arrays_1.pdf', 'pke_Ruby_Arrays_1.pdf', 'kaputt.pdf')) {
            Set-Content -Path (Join-Path $script:e2eStudent $name) -Value 'x'
        }

        $script:e2eConfig = Join-Path $script:e2eRoot 'config.psd1'
        @"
@{
    sources = @(@{ path = '$($script:e2eRoot)/quelle'; recursive = `$true; includePatterns = @('*.pdf'); excludePatterns = @() })
    aufgabenRoot = '$($script:e2eAufgaben)'
    namingConventions = @(
        @{
            match  = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$'
            rename = '{initials}{versiontag}_{praefix}_{suffix}_{aufgabennummer}'
        }
    )
    projectRoutesFile = '$($script:e2eShared)/project-routes.txt'
    projectRoutesSeedFile = '$($script:e2eShared)/project-routes.txt'
    reviewMarker = @{ enabled = `$true; kuerzelRoutesFile = '$($script:e2eShared)/kuerzel-routes.txt' }
    minFileAgeMinutes = 0
    stateFile = '$($script:e2eShared)/state.json'
    lockFile = '$($script:e2eShared)/.docflow-lock'
    log = @{ level = 'Info'; file = '$($script:e2eShared)/docflow.log' }
}
"@ | Set-Content -Path $script:e2eConfig
    }

    AfterAll {
        InModuleScope DocFlowEngine {
            $Script:DryRun = $false
            $Script:LogFilePath = $null
            $Script:CurrentLogLevel = $null
        }
    }

    It 'verändert im DryRun nichts außer dem Log' {
        Invoke-DocFlowEngine -ConfigPath $script:e2eConfig -DryRun 6>$null

        Test-Path $script:e2eAufgaben | Should -BeFalse
        Test-Path (Join-Path $script:e2eShared 'state.json') | Should -BeFalse
        Test-Path (Join-Path $script:e2eShared 'kuerzel-routes.txt') | Should -BeFalse
        Test-Path (Join-Path $script:e2eShared '.docflow-lock') | Should -BeFalse
        (Get-Content -Path (Join-Path $script:e2eShared 'docflow.log') -Raw) | Should -Match '\[DryRun\] Datei würde kopiert'
        @(Get-ChildItem -Path $script:e2eStudent -Filter '*.txt').Count | Should -Be 0
    }

    It 'kopiert gültige Abgaben, schreibt Hinweise, Zustand, Kürzel-Registry und Log und gibt die Sperre frei' {
        Invoke-DocFlowEngine -ConfigPath $script:e2eConfig 6>$null

        Test-Path (Join-Path $script:e2eAufgaben 'Java/Arrays/pke_Java_Arrays_1.pdf') | Should -BeTrue
        Test-Path (Join-Path $script:e2eAufgaben 'Ruby') | Should -BeFalse
        Test-Path (Join-Path $script:e2eStudent 'pke_Ruby_Arrays_1.pdf.NAMENSKONVENTION-FEHLER.txt') | Should -BeTrue
        Test-Path (Join-Path $script:e2eStudent 'kaputt.pdf.NAMENSKONVENTION-FEHLER.txt') | Should -BeTrue
        Test-Path (Join-Path $script:e2eShared '.docflow-lock') | Should -BeFalse
        (Get-Content -Path (Join-Path $script:e2eShared 'kuerzel-routes.txt')) | Should -Be "pke=$($script:e2eStudent)"
        (Get-Content -Path (Join-Path $script:e2eShared 'docflow.log') -Raw) | Should -Match 'Verarbeitung abgeschlossen'

        $state = Import-DocFlowState -StatePath (Join-Path $script:e2eShared 'state.json')
        @($state.processed.Keys).Count | Should -Be 1
    }

    It 'meldet eine bereits verarbeitete Datei beim zweiten Lauf nur als übersprungen' {
        Invoke-DocFlowEngine -ConfigPath $script:e2eConfig 6>$null
        Invoke-DocFlowEngine -ConfigPath $script:e2eConfig 6>$null

        (Get-Content -Path (Join-Path $script:e2eShared 'docflow.log') -Raw) | Should -Match 'Bereits in früheren Läufen verarbeitet und daher übersprungen: 1'
        @(Get-ChildItem -Path (Join-Path $script:e2eAufgaben 'Java/Arrays')).Count | Should -Be 1
    }

    It 'überspringt den Lauf, solange eine frische Sperre einer anderen Instanz besteht' {
        Set-Content -Path (Join-Path $script:e2eShared '.docflow-lock') -Value 'anderer-rechner|1|2026-01-01'

        Invoke-DocFlowEngine -ConfigPath $script:e2eConfig 6>$null

        Test-Path $script:e2eAufgaben | Should -BeFalse
        Test-Path (Join-Path $script:e2eShared '.docflow-lock') | Should -BeTrue
        Test-Path (Join-Path $script:e2eShared 'state.json') | Should -BeFalse
    }
}

Describe 'Get-DocFlowNameProposal' {
    BeforeAll {
        $script:proposalRules = @(
            @{ match = '^(?<initials>[A-Za-z]+)(?<versiontag>_v[0-9]+)?_(?<praefix>[A-Za-z]+)_(?<suffix>[A-Za-z0-9]+)_(?<aufgabennummer>[A-Za-z0-9]+)$' }
        )
        $registryPath = Join-Path $TestDrive 'proposal-registry.txt'
        Set-Content -Path $registryPath -Value @('praefix=Java', 'suffix=Arrays', 'suffix=ArrayList', 'suffix=Streams', 'praefix=Python', 'suffix=Streams', 'suffix=Dict', 'praefix=Datenbanken', 'suffix=SQL')
        $script:proposalRegistries = @{
            pairs = Get-PraefixSuffixRegistry -Path $registryPath
            flat  = [ordered]@{
                Praefixe = [System.Collections.Generic.HashSet[string]]::new([string[]]@('Java', 'Python'), [System.StringComparer]::OrdinalIgnoreCase)
                Suffixe  = [System.Collections.Generic.HashSet[string]]::new([string[]]@('Arrays', 'Dict'), [System.StringComparer]::OrdinalIgnoreCase)
            }
            none  = $null
        }
    }

    It "'<Name>' (<Registry>) wird zu '<Stem>'" -ForEach @(
        @{ Name = 'pke Java Python Streams 1'; Registry = 'pairs'; Known = $null; Stem = 'pke_PLATZHALTER_PLATZHALTER_1'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Präfix/Suffix mehrdeutig', 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Java Python Streams 1'; Registry = 'flat'; Known = $null; Stem = 'pke_PLATZHALTER_PLATZHALTER_1'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke_v2_Java_Arrays_abc'; Registry = 'pairs'; Known = $null; Stem = 'pke_v2_Java_Arrays_abc'; Compliant = $true; Version = 2; Placeholder = $false; Notes = @() }
        @{ Name = 'pke Java Arrays Blatt3'; Registry = 'pairs'; Known = $null; Stem = 'pke_Java_Arrays_Blatt3'; Compliant = $false; Version = 0; Placeholder = $false; Notes = @('Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Java ArrayList Arrays 4'; Registry = 'pairs'; Known = $null; Stem = 'pke_Java_ArrayList_4'; Compliant = $false; Version = 0; Placeholder = $false; Notes = @('Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Streams 4'; Registry = 'pairs'; Known = $null; Stem = 'pke_PLATZHALTER_Streams_4'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @("Suffix 'Streams' passt zu mehreren Präfixen (Java, Python)", 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke JavaArrays 4'; Registry = 'pairs'; Known = $null; Stem = 'pke_Java_Arrays_4'; Compliant = $false; Version = 0; Placeholder = $false; Notes = @('Präfix/Suffix aus zusammengeschriebenem Namen erkannt', 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Dict 7'; Registry = 'pairs'; Known = $null; Stem = 'pke_Python_Dict_7'; Compliant = $false; Version = 0; Placeholder = $false; Notes = @("Präfix aus Suffix 'Dict' abgeleitet", 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Java 7'; Registry = 'pairs'; Known = $null; Stem = 'pke_Java_PLATZHALTER_7'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Suffix nicht erkannt', 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'Datenbanken pke 2'; Registry = 'pairs'; Known = $null; Stem = 'pke_Datenbanken_PLATZHALTER_2'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Suffix nicht erkannt', 'Initialen aus Dateinamen übernommen') }
        @{ Name = 'Lösung Übung Java Arrays v3 Aufgabe 5 - Kopie (2)'; Registry = 'pairs'; Known = 'ahf'; Stem = 'ahf_v3_Java_Arrays_5'; Compliant = $false; Version = 3; Placeholder = $false; Notes = @() }
        @{ Name = 'Kopie von pke Java Arrays final'; Registry = 'pairs'; Known = $null; Stem = 'pke_Java_Arrays_PLATZHALTER'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Initialen aus Dateinamen übernommen', 'Aufgabennummer nicht erkannt') }
        @{ Name = 'irgendwas komplett anderes'; Registry = 'pairs'; Known = $null; Stem = 'PLATZHALTER_PLATZHALTER_PLATZHALTER_anderes'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Präfix/Suffix nicht erkannt', 'Initialen nicht erkannt') }
        @{ Name = 'pke Python Dict 9'; Registry = 'flat'; Known = $null; Stem = 'pke_Python_Dict_9'; Compliant = $false; Version = 0; Placeholder = $false; Notes = @('Initialen aus Dateinamen übernommen') }
        @{ Name = 'pke Java Arrays 1'; Registry = 'none'; Known = $null; Stem = 'pke_PLATZHALTER_PLATZHALTER_1'; Compliant = $false; Version = 0; Placeholder = $true; Notes = @('Initialen aus Dateinamen übernommen') }
    ) {
        $proposal = Get-DocFlowNameProposal -Name $Name -Rules $script:proposalRules -Registry $script:proposalRegistries[$Registry] -KnownInitials $Known

        $proposal.Stem | Should -BeExactly $Stem
        $proposal.Compliant | Should -Be $Compliant
        $proposal.Version | Should -Be $Version
        $proposal.HasPlaceholder | Should -Be $Placeholder
        @($proposal.Notes) | Should -Be $Notes
    }
}

Describe 'Import-DocFlowConfig: Standardwerte' {
    BeforeAll {
        $script:writeConfig = {
            param([string]$Extra)
            $path = Join-Path $TestDrive "cfg-$(New-Guid).psd1"
            @"
@{
    sources = @(@{ path = './quelle'; includePatterns = @('*.pdf') })
    targets = @(@{ path = './ziel' })
    namingConventions = @(@{ match = '^(?<name>.+)$'; rename = '{name}' })
$Extra
}
"@ | Set-Content -Path $path
            return $path
        }
    }

    It 'ergänzt bei einer minimalen Konfiguration alle Standardwerte' {
        $config = Import-DocFlowConfig -Path (& $script:writeConfig '')

        $config.defaultNameFormat | Should -Be '{timestamp}_{originalName}'
        $config.stateFile | Should -Be './.docflow-state.json'
        $config.stateRetentionYears | Should -Be 3
        $config.log.level | Should -Be 'Info'
        $config.log.file | Should -Be './docflow.log'
        $config.namingConventionHint.enabled | Should -BeTrue
        $config.namingConventionHint.fileNameSuffix | Should -Be '.NAMENSKONVENTION-FEHLER.txt'
        $config.namingConventionHint.message | Should -Match 'entspricht nicht dem vorgegebenen Namensschema'
        $config.duplicateHint.enabled | Should -BeTrue
        $config.duplicateHint.fileNameSuffix | Should -Be '.BEREITS-ABGEGEBEN.txt'
        $config.duplicateHint.message | Should -Match '\{suggestedName\}'
        $config.minFileAgeMinutes | Should -Be 2
        $config.copyRetry.count | Should -Be 2
        $config.copyRetry.delaySeconds | Should -Be 5
        $config.reviewMarker.enabled | Should -BeFalse
        $config.reviewMarker.pattern | Should -Be '_k-[A-Za-z0-9]+$'
        $config.reviewMarker.korrigiertFolderName | Should -Be 'Korrigiert'
        $config.reviewMarker.kuerzelRoutesFile | Should -Be './config/kuerzel-routes.txt'
        $config.unknownKuerzelHint.enabled | Should -BeTrue
        $config.unknownKuerzelHint.message | Should -Match '\{kuerzel\}'
        $config.projectRoutesSeedFile | Should -Be './config/project-routes.txt'
        $config.ContainsKey('lockFile') | Should -BeTrue
        $config.lockFile | Should -BeNullOrEmpty
        $config.lockTimeoutMinutes | Should -Be 15
        $config.sources[0].excludePatterns | Should -Be @('*.NAMENSKONVENTION-FEHLER.txt', '*.BEREITS-ABGEGEBEN.txt', '*.KUERZEL-UNBEKANNT.txt')
    }

    It 'behält ausdrücklich gesetzte falsy-Werte, wo nur fehlende Schlüssel ergänzt werden' {
        $extra = @'
    minFileAgeMinutes = 0
    copyRetry = @{ count = 0; delaySeconds = 0 }
    namingConventionHint = @{ enabled = $false; fileNameSuffix = '.EIGEN.txt' }
    duplicateHint = @{ enabled = $false }
    unknownKuerzelHint = @{ enabled = $false }
    reviewMarker = @{ enabled = $true; pattern = '_korr$' }
    projectRoutesSeedFile = ''
    log = @{ level = 'Debug' }
'@
        $config = Import-DocFlowConfig -Path (& $script:writeConfig $extra)

        $config.minFileAgeMinutes | Should -Be 0
        $config.copyRetry.count | Should -Be 0
        $config.copyRetry.delaySeconds | Should -Be 0
        $config.namingConventionHint.enabled | Should -BeFalse
        $config.namingConventionHint.fileNameSuffix | Should -Be '.EIGEN.txt'
        $config.duplicateHint.enabled | Should -BeFalse
        $config.unknownKuerzelHint.enabled | Should -BeFalse
        $config.reviewMarker.enabled | Should -BeTrue
        $config.reviewMarker.pattern | Should -Be '_korr$'
        $config.projectRoutesSeedFile | Should -Be ''
        $config.log.level | Should -Be 'Debug'
        $config.log.file | Should -BeNullOrEmpty
        $config.sources[0].excludePatterns | Should -Contain '*.EIGEN.txt'
    }

    It 'ersetzt leere Werte, wo leere Angaben als fehlend gelten' {
        $extra = @'
    defaultNameFormat = ''
    stateFile = ''
    stateRetentionYears = 0
    lockTimeoutMinutes = 0
    namingConventionHint = @{ fileNameSuffix = ''; message = '' }
'@
        $config = Import-DocFlowConfig -Path (& $script:writeConfig $extra)

        $config.defaultNameFormat | Should -Be '{timestamp}_{originalName}'
        $config.stateFile | Should -Be './.docflow-state.json'
        $config.stateRetentionYears | Should -Be 3
        $config.lockTimeoutMinutes | Should -Be 15
        $config.namingConventionHint.fileNameSuffix | Should -Be '.NAMENSKONVENTION-FEHLER.txt'
        $config.namingConventionHint.message | Should -Not -BeNullOrEmpty
    }
}
