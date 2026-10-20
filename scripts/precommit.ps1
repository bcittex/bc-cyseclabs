<#
.SYNOPSIS
    Local pre-commit checks for the Bicep project (run from anywhere inside the repo).
.EXAMPLE
    .\scripts\precommit.ps1
.EXAMPLE
    .\scripts\precommit.ps1 -SkipAzure    # offline checks only
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-security-lab-prod',
    [switch]$SkipAzure
)

$ErrorActionPreference = 'Continue'
$script:failed = $false

function Step($name) { Write-Host "`n== $name ==" -ForegroundColor Cyan }
function Pass($msg)  { Write-Host "PASS: $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "WARN: $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:failed = $true }

Set-Location (git rev-parse --show-toplevel)

# Files git would actually commit (tracked + untracked, minus .gitignore)
$committable = @(git ls-files --cached --others --exclude-standard | Where-Object { Test-Path $_ -PathType Leaf })

# 1. Required files ---------------------------------------------------------
Step 'Required files'
foreach ($f in 'main.bicep', 'network.bicep', 'README.md') {
    if (Test-Path $f) { Pass "$f exists" } else { Fail "$f is missing" }
}
$workflows = Get-ChildItem '.github/workflows/*' -Include *.yml, *.yaml -File -ErrorAction SilentlyContinue
if ($workflows) {
    Pass "workflow file(s): $($workflows.Name -join ', ')"
    if (@($workflows).Count -gt 1) { Warn 'More than one workflow file. Make sure they will not both deploy.' }
} else {
    Fail 'No workflow file in .github/workflows'
}
if ($committable -contains 'main.json') {
    Fail 'main.json is generated build output. Delete it, add it to .gitignore, and run: git rm --cached main.json (if tracked)'
}

# 2. Bicep compile and lint -------------------------------------------------
Step 'Bicep build and lint (compiles network.bicep too)'
az bicep build --file main.bicep --stdout | Out-Null
if ($LASTEXITCODE -eq 0) { Pass 'main.bicep compiles' } else { Fail 'Bicep build failed, see errors above' }

if (Test-Path 'iam/main.bicep') {
    az bicep build --file iam/main.bicep --stdout | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass 'iam/main.bicep compiles' } else { Fail 'iam/main.bicep failed to compile' }
}

# Parameter files must match the parameters declared in main.bicep
foreach ($pf in (Get-ChildItem -Recurse -File -Filter *.bicepparam)) {
    az bicep build-params --file $pf.FullName --stdout | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass "$($pf.Name) matches its template" } else { Fail "$($pf.Name) does not compile against its template" }
}

# 3. Stale references -------------------------------------------------------
Step 'Stale reference scan'
$textFiles = @($committable | Where-Object { $_ -match '\.(bicep|bicepparam|md|yml|yaml)$' })
$stale = 'resourceGroupName|scope: rg|nsg-core-prod|vnet-secure-prod|snet-core-prod|10\.0\.1\.0|priority 4000|Priority 4000'
$hits = if ($textFiles) { Select-String -Path $textFiles -Pattern $stale } else { @() }
# The network workflow must never use subscription-scope deployments (IAM under iam/ legitimately does)
$wfFiles = @($textFiles | Where-Object { $_ -like '.github/*' })
$wfHits = if ($wfFiles) { Select-String -Path $wfFiles -Pattern 'deployment sub ' } else { @() }
$hits = @($hits) + @($wfHits)
if ($hits) {
    Fail 'Stale references found:'
    $hits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
} else {
    Pass 'No stale names, scopes or priorities'
}

# 4. Secrets and identifiers ------------------------------------------------
Step 'Secret and ID scan (committable files only)'
$scanFiles = @($committable | Where-Object { $_ -match '\.(bicep|bicepparam|md|yml|yaml|json|ps1)$' -and $_ -ne 'scripts/precommit.ps1' })

# High signal: your own subscription and tenant IDs must never appear.
$sub = az account show --query id -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $sub) {
    $myIds = @($sub, (az account show --query tenantId -o tsv))
    $own = if ($scanFiles) { Select-String -Path $scanFiles -Pattern $myIds -SimpleMatch } else { @() }
    if ($own) {
        Fail 'Your subscription or tenant ID appears in a committable file:'
        $own | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
    } else {
        Pass 'Your subscription and tenant IDs do not appear in committable files'
    }
} else {
    Warn 'Not logged in to az, so your own subscription/tenant IDs cannot be checked'
}

# Secret-like strings
# Flags literal credentials only (a quoted value after "password =" or "--password"), not variables like $password.
$secret = 'client_secret|clientSecret|password\s*[:=]\s*[''"][^''"$\s][^''"]*[''"]|--password\s+[''"][^''"$][^''"]*[''"]|accountkey|sig=|PRIVATE KEY'
$sec = if ($scanFiles) { Select-String -Path $scanFiles -Pattern $secret } else { @() }
if ($sec) {
    Fail 'Secret-like strings found:'
    $sec | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
} else {
    Pass 'No secret-like strings'
}

# Informational: other GUIDs are often public Azure role IDs, so review rather than fail
$guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$other = if ($scanFiles) { Select-String -Path $scanFiles -Pattern $guid } else { @() }
if ($other) {
    Warn "$(@($other).Count) other GUID-like string(s). Review these:"
    $other | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
}

# 5. Workflow lint (optional) -----------------------------------------------
Step 'Workflow lint'
if (Get-Command actionlint -ErrorAction SilentlyContinue) {
    actionlint
    if ($LASTEXITCODE -eq 0) { Pass 'actionlint clean' } else { Fail 'actionlint reported problems' }
} else {
    Warn 'actionlint not installed (optional). Try: winget install rhysd.actionlint'
}

# 6. Azure checks -----------------------------------------------------------
if ($SkipAzure) {
    Warn 'Skipping Azure checks (-SkipAzure)'
} else {
    Step 'Azure login'
    az account show --query name -o tsv | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail 'Not logged in. Run: az login'
    } else {
        Pass 'Logged in'

        Step "ARM preflight validation against $ResourceGroup"
        $state = az deployment group validate --resource-group $ResourceGroup --template-file main.bicep --query properties.provisioningState -o tsv
        if ($LASTEXITCODE -eq 0 -and $state -eq 'Succeeded') {
            Pass 'Template validated'
        } else {
            Fail 'Validation failed, see errors above'
            Warn 'The what-if below usually prints the inner error details.'
        }

        Step 'What-if (look for Create vs Modify; nothing is deployed)'
        az deployment group what-if --resource-group $ResourceGroup --template-file main.bicep
        if ($LASTEXITCODE -eq 0) { Pass 'What-if completed' } else { Fail 'What-if failed' }
    }
}

# 7. Git summary ------------------------------------------------------------
Step 'Git status'
git status --short

Write-Host ''
if ($script:failed) {
    Write-Host 'One or more checks FAILED. Fix them before committing.' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'All checks passed. Review `git diff` and commit.' -ForegroundColor Green
}