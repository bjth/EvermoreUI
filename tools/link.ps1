<#
  Junction every EvermoreUI* addon folder in this repo into a WoW AddOns folder.
  Junctions need no admin rights or Developer Mode, and WoW follows them.

    .\tools\link.ps1                      # Forever beta (_classic_beta_)
    .\tools\link.ps1 -Flavour _retail_    # live retail
    .\tools\link.ps1 -Unlink              # remove our junctions (never real folders)
#>
param(
  [string]$Flavour = '_classic_beta_',
  [string]$WowRoot = 'C:\Program Files (x86)\World of Warcraft',
  [switch]$Unlink
)
$ErrorActionPreference = 'Stop'
$src = Split-Path $PSScriptRoot -Parent
$dst = Join-Path $WowRoot "$Flavour\Interface\AddOns"

if (-not (Test-Path $dst)) {
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  Write-Host "created $dst"
}

# The suite used to be called ForeverUI. Remove those junctions (only
# junctions, never real folders) so the old copies don't load alongside.
Get-ChildItem $dst -Directory -Filter 'ForeverUI*' -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.LinkType) {
    $_.Delete()
    Write-Host "removed  old junction $($_.Name)"
  } else {
    Write-Warning "old folder $($_.Name) is a real folder, not a junction: delete it yourself"
  }
}

# Junctions to folders that no longer exist in the repo (e.g. the SVTest
# addons, removed 25 Sep 2026). WoW would list them as missing.
Get-ChildItem $dst -Directory -Filter 'EvermoreUI*' -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.LinkType -and -not (Test-Path (Join-Path $src $_.Name))) {
    $_.Delete()
    Write-Host "removed  stale junction $($_.Name)"
  }
}

Get-ChildItem $src -Directory -Filter 'EvermoreUI*' | ForEach-Object {
  $link = Join-Path $dst $_.Name
  $existing = Get-Item $link -ErrorAction SilentlyContinue
  if ($Unlink) {
    if ($existing -and $existing.LinkType) {
      $existing.Delete()
      Write-Host "unlinked $($_.Name)"
    }
    return
  }
  if ($existing) {
    if ($existing.LinkType -and $existing.Target -contains $_.FullName) {
      Write-Host "ok       $($_.Name)"
    } else {
      Write-Warning "skip     $($_.Name): a real folder or foreign link already exists at $link"
    }
    return
  }
  New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
  Write-Host "linked   $($_.Name)"
}
