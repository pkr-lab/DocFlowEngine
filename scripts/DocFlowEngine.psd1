@{
    RootModule        = 'DocFlowEngine.psm1'
    ModuleVersion     = '0.0.0'
    GUID              = '786b3a3d-4d1a-4993-b096-f1119e27b0fe'
    Author            = 'Peter Kretzer'
    CompanyName       = 'EDV-Kretzer'
    Description       = 'Erkennt neue Dokumente in Quellordnern, benennt sie nach definierten Regeln um und kopiert sie in eine Zielstruktur.'
    PowerShellVersion = '5.1'
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('documents', 'sorting', 'automation')
            LicenseUri = 'https://github.com/pkr-lab/DocFlowEngine/blob/main/LICENSE'
            ProjectUri = 'https://github.com/pkr-lab/DocFlowEngine'
        }
    }
}
