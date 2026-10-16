BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'src', 'InventoryApi', 'InventoryApi.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module InventoryApi -ErrorAction SilentlyContinue
}

Describe 'Get-StockLevel' {
    It 'returns the stock for a known SKU' {
        Get-StockLevel -Inventory @{ 'SKU-1' = 4 } -Sku 'SKU-1' | Should -Be 4
    }

    It 'throws for an unknown SKU' {
        { Get-StockLevel -Inventory @{ 'SKU-1' = 4 } -Sku 'SKU-2' } | Should -Throw '*Unknown SKU*'
    }

    It 'rejects a malformed SKU' {
        { Get-StockLevel -Inventory @{} -Sku 'sku 1' } | Should -Throw
    }
}

Describe 'Test-ReorderNeeded' {
    It 'is <Expected> when stock is <Stock> and the reorder point is 3' -ForEach @(
        @{ Stock = 2; Expected = $true }
        @{ Stock = 3; Expected = $true }
        @{ Stock = 4; Expected = $false }
    ) {
        Test-ReorderNeeded -Inventory @{ 'SKU-7' = $Stock } -Sku 'SKU-7' -ReorderPoint 3 | Should -Be $Expected
    }
}
