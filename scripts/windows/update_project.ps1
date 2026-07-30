[CmdletBinding()]
param(
    [string]$RepositoryUrl = "https://github.com/Courtshipfy/BXCQ.git",
    [string]$DefaultBranch = "main"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$ToolsRoot = Join-Path $RepoRoot ".tools"
$GitRoot = Join-Path $ToolsRoot "git"
$CacheRoot = Join-Path $ToolsRoot "cache"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$GitExe,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs
    )

    & $GitExe @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed (exit $LASTEXITCODE): git $($GitArgs -join ' ')"
    }
}

function Download-File([string]$Uri, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    $Partial = "$Destination.part"
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
        try {
            Write-Host "Downloading: $Uri"
            if (Test-Path $Partial) { Remove-Item -Force $Partial }
            Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "BXCQ-Windows-Setup" } -Uri $Uri -OutFile $Partial
            Move-Item -Force $Partial $Destination
            return
        }
        catch {
            if ($Attempt -eq 3) { throw }
            Write-Warning "Download attempt $Attempt failed. Retrying..."
            Start-Sleep -Seconds (2 * $Attempt)
        }
    }
}

function Find-Git {
    $Candidates = @(
        (Join-Path $GitRoot "cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe"),
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe")
    )

    if (${env:ProgramFiles(x86)}) {
        $Candidates += Join-Path ${env:ProgramFiles(x86)} "Git\cmd\git.exe"
    }

    $PathGit = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($PathGit) { $Candidates = @($PathGit.Source) + $Candidates }

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path $Candidate)) { return $Candidate }
    }
    return $null
}

function Install-PortableGit {
    Write-Step "Git was not found; installing a portable copy inside .tools"
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

    try {
        $Release = Invoke-RestMethod -Headers @{ "User-Agent" = "BXCQ-Windows-Setup" } -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $Asset = $Release.assets | Where-Object { $_.name -match '^PortableGit-.+-64-bit\.7z\.exe$' } | Select-Object -First 1
        if (-not $Asset) { throw "The latest Git for Windows release does not contain a 64-bit PortableGit package." }

        $Archive = Join-Path $CacheRoot $Asset.name
        if (-not (Test-Path $Archive)) {
            Download-File $Asset.browser_download_url $Archive
        }

        if (Test-Path $GitRoot) { Remove-Item -Recurse -Force $GitRoot }
        New-Item -ItemType Directory -Force -Path $GitRoot | Out-Null
        & $Archive -y "-o$GitRoot"
        if ($LASTEXITCODE -ne 0) { throw "PortableGit extraction failed (exit $LASTEXITCODE)." }
    }
    catch {
        throw "Could not install portable Git. Check the network connection, or install Git for Windows from https://git-scm.com/download/win and run this script again.`n$($_.Exception.Message)"
    }

    $GitExe = Join-Path $GitRoot "cmd\git.exe"
    if (-not (Test-Path $GitExe)) { throw "Portable Git was downloaded, but git.exe was not found." }
    return $GitExe
}

function Configure-RepositoryGit([string]$GitExe) {
    Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "config", "core.longpaths", "true")

    $InstallRoot = Split-Path (Split-Path $GitExe -Parent) -Parent
    $CredentialManager = Join-Path $InstallRoot "mingw64\bin\git-credential-manager.exe"
    if (Test-Path $CredentialManager) {
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "config", "credential.helper", "manager")
    }
}

function Backup-NonGitFolder {
    $Parent = Split-Path $RepoRoot -Parent
    $Leaf = Split-Path $RepoRoot -Leaf
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Backup = Join-Path $Parent "$Leaf-backup-$Stamp"

    Write-Step "This folder has no Git history; creating a safety backup"
    Write-Host "Backup: $Backup"
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null

    & robocopy.exe $RepoRoot $Backup /E /R:2 /W:1 /XD .git .tools .godot build /XF .DS_Store /NFL /NDL /NJH /NJS /NP
    $RoboCopyExit = $LASTEXITCODE
    if ($RoboCopyExit -gt 7) {
        throw "Backup failed (robocopy exit $RoboCopyExit). The project was not changed."
    }
    return $Backup
}

try {
    Write-Host "BXCQ project updater" -ForegroundColor Green
    Write-Host "Project: $RepoRoot"

    $GitExe = Find-Git
    if (-not $GitExe) { $GitExe = Install-PortableGit }
    Write-Host "Git: $GitExe"

    if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
        $Backup = Backup-NonGitFolder
        Write-Step "Creating Git metadata and downloading the latest project"

        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "init", "-b", $DefaultBranch)
        Configure-RepositoryGit $GitExe
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "remote", "add", "origin", $RepositoryUrl)
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "fetch", "--prune", "origin", $DefaultBranch)
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "reset", "--hard", "origin/$DefaultBranch")
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "branch", "--set-upstream-to", "origin/$DefaultBranch", $DefaultBranch)

        Write-Host ""
        Write-Host "First-time setup completed." -ForegroundColor Green
        Write-Host "The original folder contents were backed up to: $Backup"
        exit 0
    }

    $OriginUrl = (& $GitExe -C $RepoRoot remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $OriginUrl) {
        throw "This Git repository has no 'origin' remote. Ask a developer to configure it."
    }

    Configure-RepositoryGit $GitExe

    & $GitExe -C $RepoRoot rev-parse --verify --quiet HEAD
    if ($LASTEXITCODE -ne 0) {
        $Backup = Backup-NonGitFolder
        Write-Step "Finishing first-time Git setup"
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "fetch", "--prune", "origin", $DefaultBranch)
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "reset", "--hard", "origin/$DefaultBranch")
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "branch", "--set-upstream-to", "origin/$DefaultBranch", $DefaultBranch)
        Write-Host "First-time setup completed. Backup: $Backup" -ForegroundColor Green
        exit 0
    }

    Write-Step "Protecting local work"
    $Status = (& $GitExe -C $RepoRoot status --porcelain=v1)
    $StashCreated = $false
    if ($Status) {
        $BeforeStash = (& $GitExe -C $RepoRoot rev-parse -q --verify refs/stash 2>$null)
        $StashName = "BXCQ auto-update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "stash", "push", "--include-untracked", "-m", $StashName)
        $AfterStash = (& $GitExe -C $RepoRoot rev-parse -q --verify refs/stash 2>$null)
        $StashCreated = $AfterStash -and ($AfterStash -ne $BeforeStash)
        Write-Host "Local changes were temporarily saved by Git."
    }
    else {
        Write-Host "No local changes detected."
    }

    Write-Step "Downloading project updates"
    Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "fetch", "--prune", "origin")

    $Branch = (& $GitExe -C $RepoRoot symbolic-ref --short -q HEAD 2>$null)
    if (-not $Branch) { $Branch = $DefaultBranch }
    & $GitExe -C $RepoRoot show-ref --verify --quiet "refs/remotes/origin/$Branch"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Remote branch origin/$Branch does not exist; using origin/$DefaultBranch."
        $Branch = $DefaultBranch
    }

    Invoke-Git -GitExe $GitExe -GitArgs @("-C", $RepoRoot, "merge", "--ff-only", "origin/$Branch")

    if ($StashCreated) {
        Write-Step "Restoring local work"
        & $GitExe -C $RepoRoot stash pop
        if ($LASTEXITCODE -ne 0) {
            throw "The project was updated, but Git found conflicts while restoring local changes. Nothing was discarded: the safety stash is still available. Do not edit the conflicted files; send this window to a developer."
        }
    }

    Write-Step "Update complete"
    & $GitExe -C $RepoRoot log -1 --oneline
    exit 0
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "No automatic cleanup was performed, so backups and Git stashes remain available." -ForegroundColor Yellow
    exit 1
}
