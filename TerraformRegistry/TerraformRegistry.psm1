function Connect-TerraformRegistry {
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
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $NameSpace,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Provider,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $script:tfurl) {
        Write-Warning -Message "Connect with a Terraform Registry first using Connect-TerraformRegistry"
        return
    }

    $baseUri = $script:tfurl

    if ($PSBoundParameters.ContainsKey('NameSpace')) {
        $baseUri = $baseUri, '/', $NameSpace -join ''
    }

    if ($PSBoundParameters.ContainsKey('Provider')) {
        $baseUri = $baseUri, '?provider=', $Provider -join ''
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

    $result = Invoke-RestMethod @irmArgs
    $result.modules | ForEach-Object -Process {
        if ($PSBoundParameters.ContainsKey('Name') -and $_.name -ne $Name) {
            return
        }
        $_
    }
}

function Get-TerraformModuleVersion {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject] $Module
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
        [pscustomobject] $Module
    )

    begin {
        if ($null -eq $script:tfurl) {
            Write-Warning -Message "Connect with a Terraform Registry first using Connect-TerraformRegistry"
            return
        }
    }
    process {
        $baseUri = '{0}/{1}/{2}/{3}/download' -f $script:tfurl, $Module.namespace, $Module.name, $Module.provider

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