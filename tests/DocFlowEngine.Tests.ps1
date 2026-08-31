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

Describe 'Load-Config: Defaults für neue Optionen' {
    It 'setzt sinnvolle Defaults für reviewMarker, unknownKuerzelHint und namingConventionHint, wenn sie in der Config fehlen' {
        $configPath = Join-Path $TestDrive 'minimal-config.psd1'
        @'
@{
    sources = @(@{ path = "."; recursive = $false; includePatterns = @("*.pdf"); excludePatterns = @() })
    targets = @(@{ path = "."; createIfMissing = $true; preserveSubfolders = $false })
    namingConventions = @(@{ name = "Default"; match = "^(?<name>.+)$"; rename = "{name}" })
}
'@ | Set-Content -Path $configPath

        $config = Load-Config -Path $configPath

        $config.reviewMarker.enabled | Should -BeFalse
        $config.reviewMarker.korrigiertFolderName | Should -Be 'Korrigiert'
        $config.namingConventionHint.fileNameSuffix | Should -Be '.NAMENSKONVENTION-FEHLER.txt'
        $config.unknownKuerzelHint.enabled | Should -BeTrue
        $config.lockTimeoutMinutes | Should -Be 15
    }
}
