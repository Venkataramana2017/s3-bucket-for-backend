param(
    [Parameter(Mandatory = $true)][string]$StateBucket,
    [string]$Region = 'us-east-1',
    [string]$StateKey = 's3/terraform.tfstate'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath 'terraform.tfstate')) {
        throw 'Local terraform.tfstate is required for the initial migration.'
    }
    if (Test-Path -LiteralPath 'backend.generated.tf.json') {
        throw 'Backend already configured; inspect it and use terraform init instead of repeating migration.'
    }
    $backend = @{ terraform = @{ backend = @{ s3 = @{
        bucket = $StateBucket; key = $StateKey; region = $Region
        encrypt = $true; use_lockfile = $true
    } } } }
    $backend | ConvertTo-Json -Depth 6 | Set-Content -Encoding ascii 'backend.generated.tf.json'
    # Terraform asks before copying state. Preserve local state/backups until verified.
    & ./.tools/terraform.exe init -migrate-state
    if ($LASTEXITCODE -ne 0) { throw 'State migration failed. Preserve the local state and inspect the error.' }
    & ./.tools/terraform.exe plan -detailed-exitcode
    if ($LASTEXITCODE -ne 0) { throw 'Migration needs review: verification did not return a no-change plan.' }
} finally {
    Pop-Location
}
