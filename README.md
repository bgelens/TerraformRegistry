# TerraformRegistry

Basic PowerShell Module to get information from a Terraform Registry

```powershell
Connect-TerraformRegistry
# get vnet module info from azurerm provider
Get-TerraformModule -Name vnet -Provider azurerm

# get all versions of the vnet module
Get-TerraformModule -Name vnet -Provider azurerm | Get-TerraformModuleVersion

# get downloadlink used by terraform to acquire the module
Get-TerraformModule -Name vnet -Provider azurerm | Get-TerraformModuleDownloadLink
```
