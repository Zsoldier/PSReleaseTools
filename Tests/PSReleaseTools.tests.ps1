$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modRoot = Split-Path -Parent $here | Convert-Path

Write-Host "Importing module from $script:modroot" -ForegroundColor magenta
Import-Module $modRoot -Force

InModuleScope PSReleaseTools {

$modPath = get-module psreleasetools | select path | split-path
Describe PSReleaseTools {
    It "Has exported commands" {
        {Get-Command -Module PSReleaseTools} | Should Be $true
    }

    It "Has a README.md file" {
        $f = Get-Item -Path $(Join-path -path $modpath -childpath README.md)
        $f.name | Should Be "readme.md"
    }
    Context Manifest {
        
    It "Has a manifest" {
        Get-Item -Path $modpath\PSReleaseTools.psd1 | Should Be $True
    }

    It "Has a license URI" {
        (Get-Module psreleasetools).PrivateData["PSData"]["LicenseUri"] | Should be $True
    }

    It "Has a project URI" {
        (Get-Module psreleasetools).PrivateData["PSData"]["ProjectUri"] | Should be $True
    }
    
    } #context
}

Describe Get-PSReleaseAsset {
    It "Runs without error" {
        {$script:data = Get-PSReleaseAsset -ErrorAction Stop} | Should Not Throw
    }
    It "Writes one or more objects to the pipeline" {
        $script:data.count | Should beGreaterThan 1
    }

    $FamilyValues = (Get-Command Get-PSReleaseAsset).Parameters["Family"].Attributes.ValidValues
    It "Has a validation set for Family" {
        $FamilyValues.count | Should Be 6
    }

    It "Should fail with a bad Family value" {
        {Get-PSReleaseAsset -Family FOO -ErrorAction} | Should Throw
    }
    It "Should get release assets for Ubuntu" {
        $script:dl = Get-PSReleaseAsset -Family Ubuntu
        ($script:dl).Count | Should beGreaterThan 0
    }    

    It "Result should have a Filename property" {
        ($script:dl)[0].Filename | Should Be $True
    }

    It "Result should have an URL property with https" {
        ($Script:dl)[0].url | Should Match "^https"
    }

    It "Result should have an [int] SizeMB property" {
        ($script:dl)[0].sizeMB | Should BeOfType "System.Int32"
    }
}

Describe Get-PSReleaseSummary {
    It "Runs without error" {
        {$script:sum = Get-PSReleaseSummary -ErrorAction Stop} | Should Not Throw
    }
    It "Writes a string to the pipeline" {
        $script:sum.getType().Name | Should Be "string"
    }
}

Describe Save-PSReleaseAsset {
    It "Has no tests defined at this time." {
     $true | should be $True
    }
}

}