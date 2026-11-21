<#
.SYNOPSIS
  Cut a release from main on Windows (PowerShell port of scripts/release.sh).

.DESCRIPTION
  Bumps base_version.json, regenerates CHANGELOG.md from Conventional Commits,
  commits the bump, creates the annotated vX.Y.Z tag, and prints the exact push
  commands. It never pushes.

.PARAMETER Bump
  major, minor or patch. Default: patch.

.PARAMETER DryRun
  Show the computed tag and changelog preview without writing, committing or tagging.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 patch

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 minor -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump = 'patch',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

# Always operate on the repository root, even when invoked from a subdirectory.
$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Fail 'not inside a git repository'
}
$repoRoot = $repoRoot.Trim()
Set-Location $repoRoot

$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') {
    Fail "release.ps1 must run on main (current branch: $branch)"
}

# Never release from a stale local main. A previous release build may have
# pushed a digest-pin commit to origin/main; releasing on top of the old tip
# creates an orphan tag when the branch push is rejected.
& git fetch origin main --quiet
if ($LASTEXITCODE -ne 0) {
    Fail 'could not fetch origin/main; refusing to release'
}
& git merge-base --is-ancestor origin/main HEAD
if ($LASTEXITCODE -ne 0) {
    Fail 'local main does not contain origin/main; run git pull --ff-only (or rebase) before releasing'
}

# Only tracked changes matter, matching release.sh. Untracked files are ignored.
& git diff --quiet
if ($LASTEXITCODE -ne 0) {
    & git status --short
    Fail 'release.ps1 requires a clean working tree (unstaged tracked changes)'
}
& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    & git status --short
    Fail 'release.ps1 requires a clean working tree (staged changes)'
}

$versionPath = Join-Path $repoRoot 'base_version.json'
if (-not (Test-Path $versionPath)) { Fail 'base_version.json not found' }

$data = [IO.File]::ReadAllText($versionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$major = [int]$data.major
$minor = [int]$data.minor
$patch = [int]$data.patch

switch ($Bump) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    'patch' { $patch++ }
}

$tag = "v$major.$minor.$patch"
$releasedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$newBaseVersion = @"
{
  "major": $major,
  "minor": $minor,
  "patch": $patch,
  "releasedAt": "$releasedAt",
  "releasedTag": "$tag"
}
"@

# Changelog range: commits since the previous tag, or all history before the first release.
$lastTag = (& git describe --tags --abbrev=0 2>$null)
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($lastTag)) {
    $range = "$($lastTag.Trim())..HEAD"
} else {
    $range = 'HEAD'
}
$today = [DateTime]::UtcNow.ToString('yyyy-MM-dd')

function Get-SectionItems([string]$Pattern) {
    $items = & git log --pretty=%s $range |
        Where-Object { $_ -cmatch $Pattern -and $_ -notmatch '^Merge ' }
    return @($items)
}

$breaking = @(
    & git log --pretty=%B $range |
        Where-Object { $_ -cmatch '^BREAKING CHANGE:' } |
        ForEach-Object { $_ -replace '^BREAKING CHANGE:\s*', '' }
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("# Changelog`n`n")
[void]$sb.Append("All notable changes to this project. Generated from Conventional Commits (Keep a Changelog format).`n`n")
[void]$sb.Append("## [$tag] - $today`n")

function Add-Section([string]$Title, [string[]]$Items) {
    if ($null -eq $Items -or $Items.Count -eq 0) { return }
    [void]$sb.Append("`n### $Title`n")
    foreach ($item in $Items) { [void]$sb.Append("- $item`n") }
}

Add-Section 'Added' (Get-SectionItems '^feat')
Add-Section 'Fixed' (Get-SectionItems '^fix')
Add-Section 'Changed' (Get-SectionItems '^(perf|refactor)')
Add-Section 'Chore' (Get-SectionItems '^chore')
Add-Section 'Breaking Changes' $breaking

$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'
if (Test-Path $changelogPath) {
    $oldLines = [IO.File]::ReadAllLines($changelogPath, [Text.Encoding]::UTF8)
    $start = -1
    for ($i = 0; $i -lt $oldLines.Count; $i++) {
        if ($oldLines[$i] -match '^## \[') { $start = $i; break }
    }
    if ($start -ge 0) {
        [void]$sb.Append("`n")
        for ($i = $start; $i -lt $oldLines.Count; $i++) {
            [void]$sb.Append($oldLines[$i] + "`n")
        }
    }
}

$changelog = $sb.ToString().Replace("`r`n", "`n")

if ($DryRun) {
    Write-Host "==> dry run: would bump base_version.json to $tag" -ForegroundColor Cyan
    Write-Host '==> dry run: CHANGELOG preview:' -ForegroundColor Cyan
    Write-Host $changelog
    exit 0
}

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($versionPath, $newBaseVersion + "`n", $utf8)
[IO.File]::WriteAllText($changelogPath, $changelog, $utf8)

Write-Host "==> bumped base_version.json to $tag" -ForegroundColor Green
Write-Host '==> regenerated CHANGELOG.md' -ForegroundColor Green

& git add base_version.json CHANGELOG.md
if ($LASTEXITCODE -ne 0) { Fail 'git add failed' }

& git commit -m "chore(release): $tag"
if ($LASTEXITCODE -ne 0) { Fail 'git commit failed' }

& git tag -a $tag -m "Release $tag"
if ($LASTEXITCODE -ne 0) { Fail 'git tag failed' }

Write-Host ''
Write-Host "==> Release $tag created locally. Push manually (no gh CLI):" -ForegroundColor Cyan
Write-Host ''
Write-Host "    git push origin main --follow-tags"
Write-Host ''
Write-Host '    # back-merge main into develop (GitFlow step 5):'
Write-Host '    git checkout develop; git merge main; git push origin develop; git checkout main'
