Set-StrictMode -Version Latest

# A small stand-in for the product code that tickets ask the agent to change.
# Everything outside modules/AgentFlow, scripts and .github is fair game for the agent.

<#
.SYNOPSIS
    Returns the stock level for a SKU from an inventory table.

.EXAMPLE
    Get-StockLevel -Inventory @{ 'SKU-1' = 4 } -Sku 'SKU-1'
#>
function Get-StockLevel {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [hashtable] $Inventory,
        [Parameter(Mandatory)] [ValidatePattern('^SKU-\d+$')] [string] $Sku
    )
    if (-not $Inventory.ContainsKey($Sku)) {
        throw "Unknown SKU: $Sku"
    }
    [int] $Inventory[$Sku]
}

<#
.SYNOPSIS
    True when the stock for a SKU is at or below its reorder point.

.EXAMPLE
    Test-ReorderNeeded -Inventory @{ 'SKU-1' = 2 } -Sku 'SKU-1' -ReorderPoint 3
#>
function Test-ReorderNeeded {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable] $Inventory,
        [Parameter(Mandatory)] [ValidatePattern('^SKU-\d+$')] [string] $Sku,
        [Parameter(Mandatory)] [ValidateRange(0, [int]::MaxValue)] [int] $ReorderPoint
    )
    (Get-StockLevel -Inventory $Inventory -Sku $Sku) -le $ReorderPoint
}

Export-ModuleMember -Function 'Get-StockLevel', 'Test-ReorderNeeded'
