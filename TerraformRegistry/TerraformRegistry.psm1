function Connect-TerraformRegistry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Url = 'registry.terraform.io',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $BearerToken
    )

    $baseUrl = "$url/.well-known/terraform.json"
    try {
        $result = Invoke-RestMethod -UseBasicParsing -Uri $baseUrl -ErrorAction Stop
        $script:tfurl = $url + $result.'modules.v1'.TrimEnd('/')

        # the url used to connect is a discovery url and never requires a Bearer token
        # the resulting url from discovery could require Bearer tokens

        if ($PSBoundParameters.ContainsKey('BearerToken')) {
            if ($BearerToken -notmatch "^Bearer/s.*$") {
                $BearerToken = ('Bearer {0}' -f $BearerToken)
            }
    
            $script:token = $BearerToken
        }
    } catch {
        $script:tfurl = $null
        $script:token = $null
    }
}

function Get-TerraformModule {
    [CmdletBinding(DefaultParameterSetName = 'list')]
    param (
        [Parameter(ParameterSetName = 'list')]
        [Parameter(Mandatory, ParameterSetName = 'named')]
        [ValidateNotNullOrEmpty()]
        [string] $NameSpace,

        [Parameter(ParameterSetName = 'list')]
        [Parameter(Mandatory, ParameterSetName = 'named')]
        [ValidateNotNullOrEmpty()]
        [string] $Provider,

        [Parameter(Mandatory, ParameterSetName = 'named')]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(ParameterSetName = 'named')]
        [ValidateNotNullOrEmpty()]
        [string] $Version
    )

    if ($null -eq $script:tfurl) {
        Write-Warning -Message "Connect with a Terraform Registry first using Connect-TerraformRegistry"
        return
    }

    $baseUri = $script:tfurl

    if ($PSCmdlet.ParameterSetName -eq 'list') {
        if ($PSBoundParameters.ContainsKey('NameSpace')) {
            $baseUri = $baseUri, $NameSpace -join '/'
        }

        if ($PSBoundParameters.ContainsKey('Provider')) {
            $baseUri = $baseUri, '?provider=', $Provider -join ''
        }
    } else {
        $baseUri = $baseUri, $NameSpace, $Name, $Provider -join '/'

        if ($PSBoundParameters.ContainsKey('Version')) {
            $baseUri = $baseUri, $Version -join '/'
        }
    }

    $irmArgs = @{
        Uri = $baseUri
        UseBasicParsing = $true
    }

    if ($null -ne $script:token) {
        [void] $irmArgs.Add('Headers', @{
                Authorization = $script:token
            })
    }

    if ($PSCmdlet.ParameterSetName -eq 'list') {
        $result = Invoke-RestMethod @irmArgs
        $modules = $result.modules

        while ($null -ne ($result.meta | Get-Member -MemberType NoteProperty -Name next_url)) {

            $nextQuery = ($result.meta.next_url -split '\?')[-1]
            $rootUrl, $oldQuery = $irmArgs.Uri -split '\?'
            if ($oldQuery -eq $nextQuery) {
                # we've hit a bug in api with regard to pagination where the offset is not incremented over 115
                break
            }
            $irmArgs.Uri = $rootUrl, $nextQuery -join '?'
            $result = Invoke-RestMethod @irmArgs
            $modules += $result.modules
        }

        $modules | ForEach-Object -Process {
            [void] $_.PSObject.TypeNames.Insert(0, 'TFModule')
            $_
        }
    } else {
        $result = Invoke-RestMethod @irmArgs
        [void] $result.PSObject.TypeNames.Insert(0, 'TFModule')
        $result
    }
}

function Get-TerraformModuleVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('TFModule')] $Module
    )

    begin {
        if ($null -eq $script:tfurl) {
            Write-Warning -Message "Connect with a Terraform Registry first using Connect-TerraformRegistry"
            return
        }
    }
    process {
        $baseUri = '{0}/{1}/{2}/{3}/versions' -f $script:tfurl, $Module.namespace, $Module.name, $Module.provider

        $irmArgs = @{
            Uri = $baseUri
            UseBasicParsing = $true
        }

        if ($null -ne $script:token) {
            [void] $irmArgs.Add('Headers', @{
                    Authorization = $script:token
                })
        }

        $result = Invoke-RestMethod @irmArgs
        [pscustomobject] @{
            source = $result.modules.source
            versions = $result.modules.versions.version
        }
    }
}

function Get-TerraformModuleDownloadLink {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('TFModule')] $Module,

        [switch] $Latest
    )

    begin {
        if ($null -eq $script:tfurl) {
            Write-Warning -Message "Connect with a Terraform Registry first using Connect-TerraformRegistry"
            return
        }
    }
    process {
        if ($Latest) {
            $baseUri = '{0}/{1}/{2}/{3}/download' -f $script:tfurl, $Module.namespace, $Module.name, $Module.provider
        } else {
            $baseUri = '{0}/{1}/{2}/{3}/{4}/download' -f $script:tfurl, $Module.namespace, $Module.name, $Module.provider, $Module.version
        }

        $iwrArgs = @{
            Uri = $baseUri
            UseBasicParsing = $true
        }

        if ($null -ne $script:token) {
            [void] $iwrArgs.Add('Headers', @{
                    Authorization = $script:token
                })
        }

        $result = Invoke-WebRequest @iwrArgs
        $result.Headers["X-Terraform-Get"]
    }
}
