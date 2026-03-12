param(
  [Parameter(Mandatory = $true)]
  [string]$Owner,

  [string]$Token = $env:GITHUB_TOKEN,

  [string]$OutputDirectory = ".",

  [string]$BaseName = "report"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $OutputDirectory)) {
  New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$csvPath = Join-Path $OutputDirectory ("{0}.csv" -f $BaseName)
$txtPath = Join-Path $OutputDirectory ("{0}.txt" -f $BaseName)
$xlsxPath = Join-Path $OutputDirectory ("{0}.xlsx" -f $BaseName)

$headers = @{
  Accept = "application/vnd.github+json"
  "User-Agent" = "github-report-export"
}
if ($Token) {
  $headers["Authorization"] = "Bearer $Token"
}

function Invoke-GitHubApi {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [switch]$AllowTokenFallback
  )

  try {
    return Invoke-RestMethod -Uri $Url -Headers $headers -Method Get
  }
  catch {
    if ($AllowTokenFallback -and $Token) {
      $publicHeaders = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = "github-report-export"
      }
      return Invoke-RestMethod -Uri $Url -Headers $publicHeaders -Method Get
    }
    throw
  }
}

$repos = @()
$page = 1
while ($true) {
  $repoUrl = "https://api.github.com/users/$Owner/repos?type=owner&per_page=100&page=$page"
  $batch = Invoke-GitHubApi -Url $repoUrl -AllowTokenFallback
  if (-not $batch -or $batch.Count -eq 0) {
    break
  }
  $repos += $batch
  $page++
}

$rows = @()
foreach ($repo in $repos) {
  $contribPage = 1
  while ($true) {
    $contribUrl = "https://api.github.com/repos/$($repo.full_name)/contributors?per_page=100&page=$contribPage"
    try {
      $contributors = Invoke-GitHubApi -Url $contribUrl -AllowTokenFallback
    }
    catch {
      $contributors = @()
    }

    if (-not $contributors -or $contributors.Count -eq 0) {
      break
    }

    foreach ($contributor in $contributors) {
      if ($contributor.login) {
        $rows += [pscustomobject]@{
          repository = $repo.full_name
          username   = $contributor.login
        }
      }
    }

    $contribPage++
  }
}

# Deduplicate repository/user pairs.
$rows = $rows | Sort-Object repository, username -Unique

if ($rows.Count -eq 0) {
  "repository,username" | Set-Content -Path $csvPath -Encoding UTF8
  "No data found for owner '$Owner'." | Set-Content -Path $txtPath -Encoding UTF8
}
else {
  $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
  $rows | ForEach-Object { "{0}`t{1}" -f $_.repository, $_.username } | Set-Content -Path $txtPath -Encoding UTF8
}

# Optional native Excel export when ImportExcel module exists.
$excelExported = $false
if (Get-Module -ListAvailable -Name ImportExcel) {
  try {
    $rows | Export-Excel -Path $xlsxPath -WorksheetName "repos_users" -AutoSize -ClearSheet
    $excelExported = $true
  }
  catch {
    $excelExported = $false
  }
}

Write-Host "CSV:  $csvPath"
Write-Host "TXT:  $txtPath"
if ($excelExported) {
  Write-Host "XLSX: $xlsxPath"
}
else {
  Write-Host "XLSX: not created (ImportExcel module not installed)."
}
