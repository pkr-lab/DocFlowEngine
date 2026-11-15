@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseSingularNouns'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidOverwritingBuiltInCmdlets'
        'PSUseToExportFieldsInManifest'
        'PSUseBOMForUnicodeEncodedFile'
    )
}
