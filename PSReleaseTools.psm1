#requires -version 5.0

#region Main

Function Get-PSReleaseCurrent {
[cmdletbinding()]
Param()

Begin {
    Write-Verbose "[BEGIN  ] Starting: $($MyInvocation.Mycommand)"  
    
    $uri = "https://api.github.com/repos/powershell/powershell/releases/latest"

} #begin

Process {
    Write-Verbose "[PROCESS] Getting current release information from $uri"
    $data = Invoke-Restmethod -uri $uri -Method Get

    #get the local version from the GitCommitID on v6 platforms
    #or PSVersion table for everything else
    if ($PSVersionTable.ContainsKey("GitCommitID")) {
        $local = $PSVersionTable.GitCommitID
    }
    else {
        $Local = $PSVersionTable.PSVersion
    }

    if ($data.tag_name) {
    [pscustomobject]@{
        Name = $data.name
        Version = $data.tag_name
        Released = $($data.published_at -as [datetime])
        LocalVersion = $local
      }
   } 
} #process

End {
    Write-Verbose "[END    ] Ending: $($MyInvocation.Mycommand)"
} #end

} 
 
Function Get-PSReleaseSummary {

[cmdletbinding()]
Param()

Begin {
    Write-Verbose "[BEGIN  ] Starting: $($MyInvocation.Mycommand)"  
    
    $uri = "https://api.github.com/repos/powershell/powershell/releases/latest"

} #begin

Process {
    Write-Verbose "[PROCESS] Getting latest release information from $uri"
    $data = Invoke-Restmethod -uri $uri -Method Get
    $dl = $data.assets | 
    Select @{Name="Filename";Expression={$_.name}},
    @{Name="Updated";Expression = {$_.updated_at -as [datetime]}},
    @{Name="SizeMB";Expression = {$_.size/1MB -as [int]}} | Out-String
    

    #create a here string for the details
    $out = @"

-----------------------------------------------------------
Release  : $($data.Tag_Name)
Published: $($data.Published_At -as [datetime]) 
-----------------------------------------------------------
$($data.body)

-------------
| Downloads |
-------------
$DL

"@

#write the string to the pipeline
$out

} #process

End {
    Write-Verbose "[END    ] Ending: $($MyInvocation.Mycommand)"
} #end

}

Function Save-PSReleaseAsset {

[cmdletbinding(DefaultParameterSetName="All",SupportsShouldProcess)]
Param(
[Parameter(Position = 0, HelpMessage="Where do you want to save the files?")]
[ValidateScript({
if (Test-Path $_) {
   $True
}
else {
   Throw "Cannot validate path $_"
}
})]    
[string]$Path = ".",
[Parameter(ParameterSetName="All")]
[switch]$All,
[Parameter(ParameterSetName="Name",Mandatory)]
[ValidateSet("Win7-x86","Win7-x64","Win81","Win10","MacOS","Ubuntu14","Ubuntu16","CentOS","Suse","AppImage")]
[ValidateNotNullorEmpty()]
[string[]]$Name,
[Parameter(ParameterSetName="File",Mandatory,ValueFromPipelineByPropertyName)]
[string]$Filename,
[Parameter(ParameterSetName="File",Mandatory,ValueFromPipelineByPropertyName)]
[string]$Hash,
[Parameter(ParameterSetName="File",Mandatory,ValueFromPipelineByPropertyName)]
[string]$URL,
[switch]$Passthru
)
DynamicParam {
    if ($Name -match 'Win') {
        #define a parameter attribute object
        $attributes = New-Object System.Management.Automation.ParameterAttribute
        $attributes.ValueFromPipelineByPropertyName= $True
        $attributes.HelpMessage = "Select a download format"
        $attributes.ParameterSetName = "Name"
        $attributes.DontShow = $False

        $validate = [System.Management.Automation.ValidateSetAttribute]::New("zip","msi")
        
        #define a collection for attributes
        $attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
        $attributeCollection.Add($attributes)
        $attributeCollection.Add($validate)

        #define the dynamic param
        $dynParam1 = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Format", [string], $attributeCollection)
        
        #create array of dynamic parameters
        $paramDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
        $paramDictionary.Add("Format", $dynParam1)
        #use the array
        return $paramDictionary     

    } #if
  } #dynamic parameter


Begin {
    Write-Verbose "[BEGIN  ] Starting: $($MyInvocation.Mycommand)"  
    #display PSBoundparameters formatted nicely for Verbose output  
    [string]$pb = ($PSBoundParameters | Format-Table -AutoSize | Out-String).TrimEnd()
    Write-Verbose "[BEGIN  ] PSBoundparameters: `n$($pb.split("`n").Foreach({"$("`t"*2)$_"}) | 
    Out-String) `n" 
    
    $uri = "https://api.github.com/repos/powershell/powershell/releases/latest"

    #define an internal function to download the file
    Function DL {
    [cmdletbinding(SupportsShouldProcess)]
    Param([string]$Source,[string]$Destination,[string]$hash,[switch]$Passthru)

        Write-Verbose "[DL] $Source to $Destination"
        
        if ($pscmdlet.ShouldProcess($Destination,"Downloading $source")) {
            Invoke-Webrequest -Uri $source -UseBasicParsing -DisableKeepAlive -OutFile $Destination
            Write-Verbose "[DL] Comparing file hash to $hash"
            $f = Get-FileHash -Path $Destination -Algorithm SHA256
            if ($f.hash -ne $hash) {
                Write-Warning "Hash mismatch. $Destination may be incomplete"
            }

            if ($passthru) {
                get-item $Destination
            }
        } #should process
    } #DL

} #begin

Process {
    Write-Verbose "[PROCESS] Using Parameter set $($PSCmdlet.ParameterSetName)"
    Write-Verbose "[PROCESS] Getting latest releases from $uri"
    Try {
        $data = Invoke-Restmethod -uri $uri -Method Get -ErrorAction Stop
    }
    Catch {
        Write-Warning $_.exception.message
        #bail out
        Return
    }

    if ($data.assets) {

    #parse out file names and hashes
    [regex]$rx="(?<file>[p|P]ower[s|S]hell[-|_]\d.*)\s+-\s+(?<hash>\w+)"
    $r = $rx.Matches($data.body)
    $r | foreach -Begin {$h=@{}} -process {
     $h.add($_.groups["file"].value.trim(),$_.groups["hash"].value.trim())
     }
     
      Switch ($PSCmdlet.ParameterSetName) {
      "All" {
        Write-Verbose "[PROCESS] Downloading all releases to $Path"
        foreach ($asset in $data.assets) {
            Write-Verbose "[PROCESS] ...$($Asset.name)"
            $target = Join-Path -Path $path -ChildPath $asset.Name
            DL -source $asset.browser_download_url -Destination $Target -hash $h.item($asset.name) -passthru:$passthru
        } 
      }
      "Name" {
        #download individual release files
        Foreach ($item in $name) {

            Switch ($item) {
                "Win7-x86"  { $assets = $data.assets.where({$_.name -match 'Win7-x86'})}
                "Win7-x64" { $assets = $data.assets.where({$_.name -match 'Win7-x64'}) }
                "Win81" { $assets = $data.assets.where({$_.name -match 'Win81'})}
                "Win10" { $assets = $data.assets.where({$_.name -match 'Win10'}) }
                "MacOS" { $assets = $data.assets.where({$_.name -match 'pkg'}) }
                "Ubuntu14" { $assets = $data.assets.where({$_.name -match 'ubuntu.*14'})  }
                "Ubuntu16" { $assets = $data.assets.where({$_.name -match 'ubuntu.*16'}) }
                "CentOS" { $assets = $data.assets.where({$_.name -match 'centos'}) }
                "Suse"  { $assets = $data.assets.where({$_.name -match 'suse'}) }
                "AppImage" { $assets = $data.assets.where({$_.name -match 'appimage'}) }
            } #Switch

            
            if (($assets.name -match "Win") -AND ($PSBoundParameters.ContainsKey("Format"))) {
                $type = $PSBoundParameters["format"]
                Write-Verbose "[PROCESS] Limiting download to $type files"
                $assets = $assets.Where({$_.name -match $type})
            }

            foreach ($asset in $Assets) {
                Write-Verbose "[PROCESS] ...$($asset.name)"
                $target = Join-Path -Path $path -ChildPath $asset.Name
                DL -source $asset.browser_download_url -Destination $Target -hash $h.item($asset.name) -passthru:$passthru
            } #foreach asset
        } #foreach name
      }
      "File" {
                Write-Verbose "[PROCESS] ...$($filename)"
                $target = Join-Path -Path $path -ChildPath $fileName
                DL -source $url -Destination $Target -hash $h.item($filename) -passthru:$passthru
             }
      } #switch parameter set name
    } else {
        Write-Warning "No release information was found"
    }
} #process

End {
    Write-Verbose "[END    ] Ending: $($MyInvocation.Mycommand)"
} #end

}

Function Get-PSReleaseAsset {
[cmdletbinding()]
Param(
[ValidateSet("Windows","Ubuntu","MacOS","CentOS","Suse","AppImage")]
[string[]]$Family
)

Begin {
    Write-Verbose "[BEGIN  ] Starting: $($MyInvocation.Mycommand)"  
    
    $uri = "https://api.github.com/repos/powershell/powershell/releases/latest"

} #begin

Process {
    Write-Verbose "[PROCESS] Getting latest release information from $uri"
    Try {
        $data = Invoke-Restmethod -uri $uri -Method Get -ErrorAction Stop
        
        #parse out file names and hashes
        [regex]$rx="(?<file>[p|P]ower[s|S]hell[-|_]\d.*)\s+-\s+(?<hash>\w+)"
        $r = $rx.Matches($data.body)
        $r | foreach-object -Begin {$h=@{}} -process {
            $h.add($_.groups["file"].value.trim(),$_.groups["hash"].value.trim())
        }

        Write-Verbose "[PROCESS] Found $($data.assets.count) downloads"
        $assets = $data.assets | Select @{Name="FileName";Expression={$_.Name}},
        @{Name="Family";Expression={
         Switch -regex ($_.name) {
          "Win" {"Windows"}
          "Ubuntu" {"Ubuntu"}
          "pkg" {"MacOS"}
          "centos" {"CentOS"}
          "suse" {"Suse"}
          "appimage" {"AppImage"}
         }
        }},
        @{Name="Format";Expression={
          $_.name.split(".")[-1]
        }},
        @{Name="SizeMB";Expression = {$h.size -as [int32]}},
        @{Name="Hash";Expression = {$h.item($_.name)}},
        @{Name="Created";Expression={$_.Created_at -as [datetime]}},
        @{Name="Updated";Expression={$_.Updated_at -as [datetime]}},
        @{Name="URL";Expression={$_.browser_download_Url}},
        @{Name="DownloadCount";Expression={$_.download_count}} 

        if ($Family) {
            $assets.where({$_.family -match $($family -join "|")})
        }
        
        else {
            $assets
        }
    } #Try
    catch {
        Throw $_
    }
} #process

End {
    Write-Verbose "[END    ] Ending: $($MyInvocation.Mycommand)"
} #end
}

#endregion

