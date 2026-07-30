[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$ProjectRoot = Join-Path $RepoRoot "bxcq"
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$CsProject = Join-Path $ProjectRoot "BXCQ.csproj"
$SolutionFile = Join-Path $ProjectRoot "BXCQ.sln"
$ToolsRoot = Join-Path $RepoRoot ".tools"
$CacheRoot = Join-Path $ToolsRoot "cache"
$BuildRoot = Join-Path $RepoRoot "build\windows"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Download-File([string]$Uri, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    $Partial = "$Destination.part"
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
        try {
            Write-Host "Downloading: $Uri"
            if (Test-Path $Partial) { Remove-Item -Force $Partial }
            Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "BXCQ-Windows-Builder" } -Uri $Uri -OutFile $Partial
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

function New-GodotReleaseInfo([int]$Major, [int]$Minor, [int]$Patch) {
    $SdkVersion = "$Major.$Minor.$Patch"
    if ($Patch -eq 0) { $ReleaseVersion = "$Major.$Minor" } else { $ReleaseVersion = $SdkVersion }

    return @{
        Major = $Major
        Minor = $Minor
        Patch = $Patch
        SdkVersion = $SdkVersion
        VersionPrefix = "$ReleaseVersion.stable."
        ReleaseTag = "$ReleaseVersion-stable"
        TemplateVersion = "$ReleaseVersion.stable.mono"
    }
}

function Get-ProjectGodotReleaseInfo {
    $Content = Get-Content -Raw $CsProject
    $Match = [regex]::Match($Content, 'Godot\.NET\.Sdk/(\d+)\.(\d+)\.(\d+)')
    if (-not $Match.Success) {
        throw "Cannot determine the Godot version from BXCQ.csproj. Expected Godot.NET.Sdk/x.y.z."
    }

    return New-GodotReleaseInfo ([int]$Match.Groups[1].Value) ([int]$Match.Groups[2].Value) ([int]$Match.Groups[3].Value)
}

function Get-InstalledGodotReleaseInfo([string]$Executable) {
    if (-not $Executable -or -not (Test-Path $Executable)) { return $null }
    try {
        $Version = (& $Executable --version 2>$null | Select-Object -First 1)
        $Match = [regex]::Match($Version, '^(\d+)\.(\d+)(?:\.(\d+))?\.stable\.mono')
        if (-not $Match.Success) { return $null }

        $Patch = 0
        if ($Match.Groups[3].Success) { $Patch = [int]$Match.Groups[3].Value }
        return New-GodotReleaseInfo ([int]$Match.Groups[1].Value) ([int]$Match.Groups[2].Value) $Patch
    }
    catch { return $null }
}

function Test-SupportedGodot([string]$Executable) {
    $Info = Get-InstalledGodotReleaseInfo $Executable
    return $Info -and $Info.Major -eq 4 -and $Info.Minor -ge 7
}

function Find-SystemGodot {
    $Candidates = @()
    if ($env:GODOT_EXE) { $Candidates += $env:GODOT_EXE }

    foreach ($Name in @("godot.exe", "godot4.exe")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) { $Candidates += $Command.Source }
    }

    if ($env:LOCALAPPDATA) {
        $Candidates += Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Programs\Godot") -Filter "*mono*console.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName
    }
    if ($env:ProgramFiles) {
        $Candidates += Get-ChildItem -Path (Join-Path $env:ProgramFiles "Godot*") -Filter "*mono*console.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName
    }
    if ($env:USERPROFILE) {
        foreach ($Folder in @("Downloads", "Desktop")) {
            $Candidates += Get-ChildItem -Path (Join-Path $env:USERPROFILE $Folder) -Filter "*mono*console.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName
        }
    }

    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (Test-SupportedGodot $Candidate) { return $Candidate }
    }
    return $null
}

function Install-LocalGodot($ReleaseInfo) {
    $GodotRoot = Join-Path $ToolsRoot ("godot\" + $ReleaseInfo.ReleaseTag)
    $Existing = Get-ChildItem -Path $GodotRoot -Filter "*_console.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $ExistingInfo = $null
    if ($Existing) { $ExistingInfo = Get-InstalledGodotReleaseInfo $Existing.FullName }
    if ($ExistingInfo -and $ExistingInfo.ReleaseTag -eq $ReleaseInfo.ReleaseTag) {
        New-Item -ItemType File -Force -Path (Join-Path $Existing.DirectoryName "_sc_") | Out-Null
        return $Existing.FullName
    }

    Write-Step "Godot .NET $($ReleaseInfo.SdkVersion) was not found; installing a portable copy"
    $AssetName = "Godot_v$($ReleaseInfo.ReleaseTag)_mono_win64.zip"
    $Archive = Join-Path $CacheRoot $AssetName
    $Uri = "https://github.com/godotengine/godot/releases/download/$($ReleaseInfo.ReleaseTag)/$AssetName"
    if (-not (Test-Path $Archive)) { Download-File $Uri $Archive }

    if (Test-Path $GodotRoot) { Remove-Item -Recurse -Force $GodotRoot }
    New-Item -ItemType Directory -Force -Path $GodotRoot | Out-Null
    Expand-Archive -Path $Archive -DestinationPath $GodotRoot -Force

    $Godot = Get-ChildItem -Path $GodotRoot -Filter "*_console.exe" -Recurse | Select-Object -First 1
    if (-not $Godot) { throw "Godot was downloaded, but the console executable was not found." }

    # Self-contained mode keeps editor data and export templates inside .tools.
    New-Item -ItemType File -Force -Path (Join-Path $Godot.DirectoryName "_sc_") | Out-Null
    return $Godot.FullName
}

function Get-TemplateRoot([string]$GodotExe, [bool]$IsLocal, [string]$TemplateVersion) {
    if ($IsLocal) {
        return Join-Path (Split-Path $GodotExe -Parent) "editor_data\export_templates\$TemplateVersion"
    }
    if (-not $env:APPDATA) { throw "APPDATA is not available, so Godot export templates cannot be installed." }
    return Join-Path $env:APPDATA "Godot\export_templates\$TemplateVersion"
}

function Install-ExportTemplates($ReleaseInfo, [string]$TemplateRoot) {
    $Sentinel = Join-Path $TemplateRoot "windows_release_x86_64.exe"
    if (Test-Path $Sentinel) { return }

    Write-Step "Windows export templates are missing; installing them"
    $AssetName = "Godot_v$($ReleaseInfo.ReleaseTag)_mono_export_templates.tpz"
    $Archive = Join-Path $CacheRoot $AssetName
    $Uri = "https://github.com/godotengine/godot/releases/download/$($ReleaseInfo.ReleaseTag)/$AssetName"
    if (-not (Test-Path $Archive)) { Download-File $Uri $Archive }

    $ZipCopy = Join-Path $CacheRoot ($AssetName + ".zip")
    Copy-Item -Force $Archive $ZipCopy
    $TempExtract = Join-Path $env:TEMP ("bxcq-templates-" + [Guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -Path $ZipCopy -DestinationPath $TempExtract -Force
        $Source = Join-Path $TempExtract "templates"
        if (-not (Test-Path $Source)) { $Source = $TempExtract }
        New-Item -ItemType Directory -Force -Path $TemplateRoot | Out-Null
        Copy-Item -Path (Join-Path $Source "*") -Destination $TemplateRoot -Recurse -Force
    }
    finally {
        if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
    }

    if (-not (Test-Path $Sentinel)) { throw "Export templates were extracted, but the Windows release template was not found." }
}

function Test-DotNet8([string]$Executable) {
    if (-not $Executable -or -not (Test-Path $Executable)) { return $false }
    try {
        $Sdks = & $Executable --list-sdks 2>$null
        return [bool]($Sdks | Where-Object { $_ -match '^8\.' })
    }
    catch { return $false }
}

function Resolve-DotNet {
    $LocalDotNet = Join-Path $ToolsRoot "dotnet\dotnet.exe"
    if (Test-DotNet8 $LocalDotNet) { return $LocalDotNet }

    $SystemDotNet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($SystemDotNet -and (Test-DotNet8 $SystemDotNet.Source)) { return $SystemDotNet.Source }

    Write-Step ".NET 8 SDK was not found; installing a portable copy"
    $InstallRoot = Join-Path $ToolsRoot "dotnet"
    $Installer = Join-Path $CacheRoot "dotnet-install.ps1"
    Download-File "https://dot.net/v1/dotnet-install.ps1" $Installer
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Installer -Channel 8.0 -Architecture x64 -InstallDir $InstallRoot -NoPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-DotNet8 $LocalDotNet)) {
        throw ".NET 8 SDK installation failed. You can install it manually from https://dotnet.microsoft.com/download/dotnet/8.0 and retry."
    }
    return $LocalDotNet
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments, [string]$Description) {
    Write-Host "> $Description"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description failed (exit $LASTEXITCODE)." }
}

function Set-TemporaryGodotSdk([string]$SdkVersion) {
    $Content = Get-Content -Raw $CsProject
    $SdkPattern = [regex]'Godot\.NET\.Sdk/\d+\.\d+\.\d+'
    $Adjusted = $SdkPattern.Replace($Content, "Godot.NET.Sdk/$SdkVersion", 1)
    if ($Adjusted -eq $Content) { throw "Could not update the temporary Godot SDK version in BXCQ.csproj." }

    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($CsProject, $Adjusted, $Utf8NoBom)
}

$OriginalCsProject = $null
$CsProjectWasAdjusted = $false
$ScriptExitCode = 0
try {
    Write-Host "BXCQ Windows packager" -ForegroundColor Green
    Write-Host "Project: $ProjectRoot"

    if (-not (Test-Path $ProjectFile)) { throw "project.godot was not found: $ProjectFile" }
    if (-not (Test-Path $CsProject)) { throw "BXCQ.csproj was not found: $CsProject" }
    if (-not (Test-Path $SolutionFile)) { throw "BXCQ.sln is missing. Godot cannot export a C# project without its solution file." }
    if (-not (Test-Path (Join-Path $ProjectRoot "export_presets.cfg"))) { throw "export_presets.cfg is missing." }

    $ProjectReleaseInfo = Get-ProjectGodotReleaseInfo
    Write-Host "Project Godot .NET SDK: $($ProjectReleaseInfo.SdkVersion)"

    $DotNetExe = Resolve-DotNet
    $env:DOTNET_ROOT = Split-Path $DotNetExe -Parent
    $env:PATH = "$($env:DOTNET_ROOT);$($env:PATH)"
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    $env:DOTNET_NOLOGO = "1"
    Write-Host ".NET: $DotNetExe"

    $GodotExe = Find-SystemGodot
    $IsLocalGodot = $false
    if (-not $GodotExe) {
        $GodotExe = Install-LocalGodot $ProjectReleaseInfo
        $IsLocalGodot = $true
    }
    elseif ($GodotExe.StartsWith($ToolsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $IsLocalGodot = $true
    }
    Write-Host "Godot: $GodotExe"

    $ReleaseInfo = Get-InstalledGodotReleaseInfo $GodotExe
    if (-not $ReleaseInfo -or $ReleaseInfo.Major -ne 4 -or $ReleaseInfo.Minor -lt 7) {
        throw "Godot must be a stable Mono build from the 4.x series, version 4.7 or newer."
    }
    Write-Host "Selected Godot version: $($ReleaseInfo.SdkVersion)"

    if ($ProjectReleaseInfo.SdkVersion -ne $ReleaseInfo.SdkVersion) {
        Write-Step "Temporarily matching the C# SDK to Godot $($ReleaseInfo.SdkVersion)"
        $OriginalCsProject = Get-Content -Raw $CsProject
        Set-TemporaryGodotSdk $ReleaseInfo.SdkVersion
        $CsProjectWasAdjusted = $true
    }

    $TemplateRoot = Get-TemplateRoot $GodotExe $IsLocalGodot $ReleaseInfo.TemplateVersion
    Install-ExportTemplates $ReleaseInfo $TemplateRoot

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $StageRoot = Join-Path $BuildRoot "BXCQ-Windows-$Stamp"
    $OutputExe = Join-Path $StageRoot "BXCQ.exe"
    $OutputZip = Join-Path $BuildRoot "BXCQ-Windows-$Stamp.zip"
    New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null

    Write-Step "Restoring and compiling C#"
    Invoke-Checked -Executable $DotNetExe -Arguments @("build", $CsProject, "--configuration", "Release") -Description "dotnet build"

    Write-Step "Importing project resources"
    Invoke-Checked -Executable $GodotExe -Arguments @("--headless", "--path", $ProjectRoot, "--editor", "--quit") -Description "Godot project check/import"

    Write-Step "Exporting Windows release"
    Invoke-Checked -Executable $GodotExe -Arguments @("--headless", "--path", $ProjectRoot, "--export-release", "Windows Desktop", $OutputExe) -Description "Godot Windows export"
    if (-not (Test-Path $OutputExe)) { throw "Godot reported success, but the exported executable was not created." }

    $Commit = "not-a-git-checkout"
    $Git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($Git -and (Test-Path (Join-Path $RepoRoot ".git"))) {
        $DetectedCommit = (& $Git.Source -C $RepoRoot rev-parse --short HEAD 2>$null)
        if ($DetectedCommit) { $Commit = $DetectedCommit }
    }
    @(
        "Build time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        "Commit: $Commit",
        "Godot SDK: $($ReleaseInfo.SdkVersion)",
        ".NET: $(& $DotNetExe --version)"
    ) | Set-Content -Encoding UTF8 (Join-Path $StageRoot "build-info.txt")

    Write-Step "Creating zip package"
    Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $OutputZip -CompressionLevel Optimal

    Write-Host ""
    Write-Host "Build completed successfully." -ForegroundColor Green
    Write-Host "Folder: $StageRoot"
    Write-Host "Zip:    $OutputZip"
    try {
        Start-Process explorer.exe -ArgumentList "/select,`"$OutputZip`""
    }
    catch {
        Write-Warning "The package was created, but Explorer could not be opened automatically."
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Downloaded tools and partial build output were kept so the next attempt can continue." -ForegroundColor Yellow
    $ScriptExitCode = 1
}
finally {
    if ($CsProjectWasAdjusted -and $null -ne $OriginalCsProject) {
        try {
            $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [IO.File]::WriteAllText($CsProject, $OriginalCsProject, $Utf8NoBom)
            Write-Host "Restored the original BXCQ.csproj SDK version."
        }
        catch {
            Write-Host "ERROR: Could not restore BXCQ.csproj: $($_.Exception.Message)" -ForegroundColor Red
            $ScriptExitCode = 1
        }
    }
}

exit $ScriptExitCode
