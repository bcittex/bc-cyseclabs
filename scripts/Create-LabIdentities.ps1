<#
.SYNOPSIS
    Creates lab Entra ID groups and test users with Azure CLI.
.DESCRIPTION
    Idempotent: existing groups, users and memberships are left alone.
    New users get a random one-time password, shown once at the end, and must
    change it at first sign-in. No credentials are stored in this file.
.EXAMPLE
    .\scripts\Create-LabIdentities.ps1
#>

function New-RandomPassword {
    param([int]$Length = 20)
    # Symbols are limited to characters that survive az.cmd argument parsing on Windows.
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#-_+')
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $next = {
        $b = New-Object byte[] 4
        $rng.GetBytes($b)
        [BitConverter]::ToUInt32($b, 0)
    }
    $pick = { param([string]$Set) $Set[[int]((& $next) % $Set.Length)] }

    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($s in $sets) { $chars.Add((& $pick $s)) }      # guarantee one of each class
    $all = $sets -join ''
    while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }
    -join ($chars | Sort-Object { & $next })                # shuffle
}

$failed = $false

# --- Sign-in check and domain -------------------------------------------------
$signedIn = az ad signed-in-user show --query userPrincipalName --output tsv
if ($LASTEXITCODE -ne 0 -or -not $signedIn) {
    Write-Host 'Not signed in. Run: az login' -ForegroundColor Red
    exit 1
}
$domain = $signedIn.Split('@')[1]
Write-Host "Using domain: $domain" -ForegroundColor Cyan

# --- 1. Groups ----------------------------------------------------------------
$groups = @(
    @{ Name = 'SecOps-Auditors-Group';   Nickname = 'SecOpsAuditors';   Desc = 'Security audit team' },
    @{ Name = 'SecOps-Engineers-Group';  Nickname = 'SecOpsEngineers';  Desc = 'Security engineering team' },
    @{ Name = 'Cloud-Operations-Group';  Nickname = 'CloudOps';         Desc = 'Infrastructure operations team' }
)
$groupMap = @{}

Write-Host "`n--- Groups ---" -ForegroundColor Yellow
foreach ($g in $groups) {
    # Exact match. 'az ad group list --display-name' is a prefix match and can return the wrong group.
    $groupId = az ad group list --filter "displayName eq '$($g.Name)'" --query '[0].id' --output tsv
    if (-not $groupId) {
        $groupId = az ad group create --display-name $g.Name --mail-nickname $g.Nickname --description $g.Desc --query id --output tsv
        if ($LASTEXITCODE -ne 0 -or -not $groupId) {
            Write-Host "FAILED to create group: $($g.Name)" -ForegroundColor Red
            $failed = $true
            continue
        }
        Write-Host "Created group: $($g.Name)" -ForegroundColor Green
    } else {
        Write-Host "Group already exists: $($g.Name)" -ForegroundColor DarkGreen
    }
    $groupMap[$g.Name] = $groupId
}

# --- 2. Users and memberships -------------------------------------------------
$users = @(
    @{ DisplayName = 'Jane Auditor';  Prefix = 'jane.auditor';  Group = 'SecOps-Auditors-Group' },
    @{ DisplayName = 'Alex Security'; Prefix = 'alex.security'; Group = 'SecOps-Engineers-Group' },
    @{ DisplayName = 'Morgan Ops';    Prefix = 'morgan.ops';    Group = 'Cloud-Operations-Group' }
)
$newCredentials = @()

Write-Host "`n--- Users and memberships ---" -ForegroundColor Yellow
foreach ($u in $users) {
    $upn = "$($u.Prefix)@$domain"

    $userId = az ad user show --id $upn --query id --output tsv 2>$null
    if (-not $userId) {
        $password = New-RandomPassword
        $userId = az ad user create --display-name $u.DisplayName --user-principal-name $upn --password $password --force-change-password-next-sign-in true --query id --output tsv
        if ($LASTEXITCODE -ne 0 -or -not $userId) {
            Write-Host "FAILED to create user: $($u.DisplayName)" -ForegroundColor Red
            $failed = $true
            continue
        }
        Write-Host "Created user: $($u.DisplayName) ($upn)" -ForegroundColor Green
        $newCredentials += [pscustomobject]@{ User = $upn; OneTimePassword = $password }
    } else {
        Write-Host "User already exists: $($u.DisplayName) ($upn)" -ForegroundColor DarkGreen
    }

    $groupId = $groupMap[$u.Group]
    if ($groupId -and $userId) {
        $isMember = az ad group member check --group $groupId --member-id $userId --query value --output tsv
        if ($isMember -eq 'false') {
            az ad group member add --group $groupId --member-id $userId
            if ($LASTEXITCODE -eq 0) { Write-Host "  Added to $($u.Group)" -ForegroundColor Cyan }
            else { Write-Host "  FAILED to add to $($u.Group)" -ForegroundColor Red; $failed = $true }
        } else {
            Write-Host "  Already a member of $($u.Group)" -ForegroundColor DarkCyan
        }
    }
}

# --- Summary ------------------------------------------------------------------
if ($newCredentials.Count -gt 0) {
    Write-Host "`nOne-time passwords (shown once, users must change them at first sign-in):" -ForegroundColor Yellow
    $newCredentials | Format-Table -AutoSize
    Write-Host 'Copy these now. Do not paste them into the repo, chats or tickets.' -ForegroundColor Yellow
}

if ($failed) {
    Write-Host "`nCompleted with errors. Review the messages above." -ForegroundColor Red
    exit 1
}
Write-Host "`nIdentity setup completed." -ForegroundColor Green
