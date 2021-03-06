function ConvertTo-Dsc {
    <#
.SYNOPSIS
    Converts json DSL files to PSCustomObject
.DESCRIPTION
    Converts json DSL files to PSCustomObjects that Invoke-DSCResource can consume. All property
    objects will be converted to hashtables for the property cmdlet of Invoke-DSCResource. ModuleName
    is discovered dynamically  from the resource name provided in the json.
.PARAMETER Path
    Specifies the path to a .json file.
.PARAMETER InputObject
    Specifies an InputObject containing json synatx
.EXAMPLE
    ConvertTo-Dsc -Path 'c:\json\example.json'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path', Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'InputObject', Position = 1)]
        [object[]]$InputObject
    )
    begin {

        if ($PSBoundParameters.ContainsKey('Path')) {
            $data = Get-Content -Path $path -Raw | ConvertFrom-Json
        }
        else {
            $data = $InputObject | ConvertFrom-Json
        }

        $alldscObj = @()
    }
    process {
        $dscResourceProperties = $data.DSCResourcesToExecute.PSObject.Properties |
            Where-Object { $_.MemberType -eq "NoteProperty"; };
        foreach ($dscResourceProperty in $dscResourceProperties) {
            $dscResource = $dscResourceProperty.Value
            $dscObj = New-Object psobject

            if ($dscResource.dscResourceName) {
                $resource = (Get-DscResource -Name $dscResource.dscResourceName | Sort-Object Version -Descending)[0]
            } else {
                throw "dscResourceName property is null for [$($dscResourceProperty.Name)]"
            }

            if ($dscResource.dscResourceName -eq 'file') {
                $module = 'PSDesiredStateConfiguration'
            } else {
                $module = $resource.ModuleName
            }

            if ($null -ne $data.Modules.$module -and $data.Modules -match $module)
            {
                $moduleVersion = ($data.Modules).$module

                if ($resource.Version -notmatch $moduleVersion)
                {
                    $resource = Get-DscResource -Name $dscResource.dscResourceName | Where-Object Version -Match $moduleVersion
                }
            }


            $Config = @{
                Name     = ($dscResource.dscResourceName)
                Property = @{
                }
            }
            $configkeys = ($dscResource.psobject.Properties -notmatch '(dsc)?ResourceName')
            foreach ($configKey in $configKeys) {
                $prop = $resource.Properties | Where-Object {$_.Name -eq $configKey.Name}

                if ($ConfigKey.Value -is [array] -and $prop.PropertyType -eq '[string]'){
                    $ConfigKey.Value = $configKey.Value | Out-String
                }
                if ($ConfigKey.Value -is [array]) {
                    foreach ($key in $ConfigKey.Value) {
                        if ($key.psobject.Properties['CimType']) {
                            #Create new CIM object
                            $cimhash = @{}
                            $key.Properties.psobject.Properties | ForEach-Object {
                                $cimhash[$_.Name] = $_.Value
                            }
                            if ($prop.PropertyType -match '\[\w+\[\]\]') {
                                [ciminstance[]]$value += New-CimInstance -ClassName $key.CimType -Property $cimhash -ClientOnly
                            }
                            else {
                                [ciminstance]$value = New-CimInstance -ClassName $key.CimType -Property $cimhash -ClientOnly
                            }
                        }
                        else {
                            $value = $configKey.Value
                        }
                    }
                    $config.Property.Add($configKey.Name, $value)
                    Remove-Variable -Name Value -Force
                }
                elseif ($prop.PropertyType -eq '[PSCredential]') {
                    $credSplit = $configKey.Value -split '\\'
                    $cred = New-Object System.Management.Automation.PSCredential ($credSplit[0], ($credSplit[1] | ConvertTo-SecureString -AsPlainText -Force))
                    [System.Management.Automation.PSCredential]$value = $cred
                    $config.Property.Add($configKey.Name, $value)
                    Remove-Variable -Name Value -Force
                }
                else {
                    $config.Property.Add($configKey.Name, $configKey.Value)
                }
            }
            $dscObj | Add-Member -MemberType NoteProperty -Name resourceName -Value $dscResourceProperty.Name
            $dscObj | Add-Member -MemberType NoteProperty -Name dscResourceName -Value $dscResource.dscResourceName
            $dscObj | Add-Member -MemberType NoteProperty -Name ModuleName -Value $module

            if ($null -ne $data.Modules.$module -and $data.Modules -match $module)
            {
                $dscObj | Add-Member -MemberType NoteProperty -Name ModuleVersion -Value $moduleVersion
            }
            else
            {
                $dscObj | Add-Member -MemberType NoteProperty -Name ModuleVersion -Value $null
            }

            $dscObj | Add-Member -MemberType NoteProperty -Name Property -Value $Config.Property
            $alldscObj += $dscObj
        }
    }
    end {
        return $alldscObj
    }
}
