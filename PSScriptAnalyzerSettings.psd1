@{
    # ParseError is how a 5.1 host reports PS7-only syntax (??, ternary, &&).
    Severity     = @('Error', 'Warning', 'ParseError')
    IncludeRules = @(
        'PSUseApprovedVerbs'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPlainTextForPassword'
        'PSUseCompatibleSyntax'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidUsingEmptyCatchBlock'
    )
    Rules        = @{
        # Flags PS 6+ only syntax (??, ternary, &&, -Parallel) so it never reaches 5.1.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}
