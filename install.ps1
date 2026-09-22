[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$ZenPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$rawBase = 'https://raw.githubusercontent.com/wahyuabrory/little-zen/main'
$script:TempPayload = $null

function Stop-Install([string]$Message) {
    Write-Error $Message
    exit 1
}

function Get-RemotePayload {
    $script:TempPayload = Join-Path ([IO.Path]::GetTempPath()) ('little-zen-' + [guid]::NewGuid())
    $files = @(
        'littleZen.uc.js',
        'little-zen.css',
        'vendor/fx-autoconfig/program/config.js',
        'vendor/fx-autoconfig/program/defaults/pref/config-prefs.js',
        'vendor/fx-autoconfig/profile/chrome/utils/boot.sys.mjs',
        'vendor/fx-autoconfig/profile/chrome/utils/chrome.manifest',
        'vendor/fx-autoconfig/profile/chrome/utils/fs.sys.mjs',
        'vendor/fx-autoconfig/profile/chrome/utils/module_loader.mjs',
        'vendor/fx-autoconfig/profile/chrome/utils/uc_api.sys.mjs',
        'vendor/fx-autoconfig/profile/chrome/utils/utils.sys.mjs'
    )
    foreach ($file in $files) {
        $destination = Join-Path $script:TempPayload $file
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/$file" -OutFile $destination
        } catch {
            Stop-Install "Could not download $rawBase/$file"
        }
    }
    return $script:TempPayload
}

function Get-IniSections([string]$Path) {
    $sections = @()
    $current = $null
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line -match '^\[(.+)\]$') {
            $current = [pscustomobject]@{ Name = $Matches[1]; Values = @{} }
            $sections += $current
        } elseif ($current -and $line -match '^([^;#][^=]*)=(.*)$') {
            $current.Values[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $sections
}

function Resolve-Profile([string]$Requested) {
    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Container)) {
            Stop-Install "Profile directory not found: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $root = Join-Path $env:APPDATA 'zen'
    $ini = Join-Path $root 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini)) {
        Stop-Install "Zen profiles.ini was not found at $ini. Pass -ProfilePath explicitly."
    }

    $sections = Get-IniSections $ini
    $profiles = @($sections | Where-Object Name -Like 'Profile*' | ForEach-Object {
        if (-not $_.Values.ContainsKey('Path')) { return }
        $path = $_.Values.Path
        if ($_.Values.IsRelative -ne '0') { $path = Join-Path $root $path }
        if (Test-Path -LiteralPath $path -PathType Container) {
            [pscustomobject]@{
                Path = (Resolve-Path -LiteralPath $path).Path
                Default = ($_.Values.Default -eq '1')
            }
        }
    })

    $installDefault = @($sections | Where-Object Name -Like 'Install*' | ForEach-Object {
        if ($_.Values.ContainsKey('Default')) {
            $path = $_.Values.Default
            if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $root $path }
            if (Test-Path -LiteralPath $path -PathType Container) { (Resolve-Path -LiteralPath $path).Path }
        }
    } | Select-Object -Unique)
    if ($installDefault.Count -eq 1) { return $installDefault[0] }

    $defaults = @($profiles | Where-Object Default | Select-Object -ExpandProperty Path -Unique)
    if ($defaults.Count -eq 1) { return $defaults[0] }
    $paths = @($profiles | Select-Object -ExpandProperty Path -Unique)
    if ($paths.Count -eq 1) { return $paths[0] }

    $choices = if ($paths.Count) { $paths -join "`n  " } else { '(none)' }
    Stop-Install "Could not select one Zen profile. Run again with -ProfilePath. Found:`n  $choices"
}

function Resolve-ZenDirectory([string]$Requested) {
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    $command = Get-Command zen.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $candidates += @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Zen Browser'),
        (Join-Path $env:ProgramFiles 'Zen Browser')
    )
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Zen Browser') }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            if ((Split-Path -Leaf $candidate) -ieq 'zen.exe') { return (Split-Path -Parent (Resolve-Path -LiteralPath $candidate).Path) }
        } elseif (Test-Path -LiteralPath (Join-Path $candidate 'zen.exe') -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    Stop-Install 'Zen installation was not found. Pass -ZenPath with the directory that contains zen.exe.'
}

function Copy-Strict([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash) {
            Stop-Install "A different autoconfig file already exists: $Destination`nIt was not overwritten."
        }
        return
    }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination
    } catch {
        $rerun = if ($PSCommandPath) {
            "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProfilePath `"$profile`" -ZenPath `"$zenDir`""
        } else {
            "powershell -ExecutionPolicy Bypass -Command `"irm $rawBase/install.ps1 | iex`""
        }
        Stop-Install "Cannot write to the Zen installation: $Destination`nClose Zen, open PowerShell as Administrator, then run:`n$rerun"
    }
}

function Write-Atomic([string]$Path, [string]$Content) {
    $temp = "$Path.little-zen.tmp"
    [IO.File]::WriteAllText($temp, $Content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

if (Get-Process -Name zen -ErrorAction SilentlyContinue) {
    Stop-Install 'Zen is running. Close all Zen windows and run the installer again.'
}

$repo = $PSScriptRoot
if (-not $repo -or -not (Test-Path -LiteralPath (Join-Path $repo 'littleZen.uc.js') -PathType Leaf)) {
    $repo = Get-RemotePayload
}
$profile = Resolve-Profile $ProfilePath
$zenDir = Resolve-ZenDirectory $ZenPath
$vendor = Join-Path $repo 'vendor\fx-autoconfig'

foreach ($required in @('littleZen.uc.js', 'little-zen.css', 'vendor\fx-autoconfig\program\config.js', 'vendor\fx-autoconfig\program\defaults\pref\config-prefs.js')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $required) -PathType Leaf)) { Stop-Install "Installer payload is missing: $required" }
}

Copy-Strict (Join-Path $vendor 'program\config.js') (Join-Path $zenDir 'config.js')
Copy-Strict (Join-Path $vendor 'program\defaults\pref\config-prefs.js') (Join-Path $zenDir 'defaults\pref\config-prefs.js')

$chrome = Join-Path $profile 'chrome'
$jsDir = Join-Path $chrome 'JS'
$cssDir = Join-Path $chrome 'CSS'
$utilsDir = Join-Path $chrome 'utils'
New-Item -ItemType Directory -Force -Path $jsDir, $cssDir, $utilsDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'littleZen.uc.js') -Destination (Join-Path $jsDir 'littleZen.uc.js') -Force
Copy-Item -LiteralPath (Join-Path $repo 'little-zen.css') -Destination (Join-Path $cssDir 'little-zen.css') -Force
Copy-Item -Path (Join-Path $vendor 'profile\chrome\utils\*') -Destination $utilsDir -Force

$userChrome = Join-Path $chrome 'userChrome.css'
$import = '@import url("CSS/little-zen.css");'
$chromeText = if (Test-Path -LiteralPath $userChrome) { [IO.File]::ReadAllText($userChrome) } else { '' }
if ($chromeText -notmatch '(?m)^\s*@import\s+url\(["'']CSS/little-zen\.css["'']\);\s*$') {
    Write-Atomic $userChrome ($import + "`n" + $chromeText)
}

$userJs = Join-Path $profile 'user.js'
$pref = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
$userText = if (Test-Path -LiteralPath $userJs) { [IO.File]::ReadAllText($userJs) } else { '' }
if ($userText -match '(?m)^\s*user_pref\("toolkit\.legacyUserProfileCustomizations\.stylesheets",\s*(?:true|false)\s*\);\s*$') {
    $userText = [regex]::Replace($userText, '(?m)^\s*user_pref\("toolkit\.legacyUserProfileCustomizations\.stylesheets",\s*(?:true|false)\s*\);\s*$', $pref)
} else {
    if ($userText.Length -and -not $userText.EndsWith("`n")) { $userText += "`n" }
    $userText += $pref + "`n"
}
Write-Atomic $userJs $userText

Write-Host 'Little Zen installed without Sine.' -ForegroundColor Green
Write-Host "Profile: $profile"
Write-Host "Zen:     $zenDir"
Write-Host 'Start Zen. If the mod does not load, open about:support, select Clear startup cache, and restart.'

if ($script:TempPayload) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedPayload = [IO.Path]::GetFullPath($script:TempPayload)
    if ($resolvedPayload.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedPayload -Recurse -Force
    }
}
