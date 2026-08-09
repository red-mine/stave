param(
  [string]$DataPath = $(if ($env:TDX_DATA_PATH) { $env:TDX_DATA_PATH } else { "C:\new_tdx\vipdoc" }),
  [string]$WorkDirectory = "",
  [uri]$MetadataUri = "https://data.tdx.com.cn/vipdoc/_hsjdayinfo.js",
  [uri]$ArchiveUri = "https://data.tdx.com.cn/vipdoc/hsjday.zip"
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$work = if ($WorkDirectory) {
  [System.IO.Path]::GetFullPath($WorkDirectory)
} else {
  Join-Path $repository "tmp\tdx-update"
}
$dataRoot = [System.IO.Path]::GetFullPath($DataPath)
$archive = Join-Path $work "hsjday.zip"
$partialArchive = Join-Path $work "hsjday.zip.part"
$staging = Join-Path $work "staging"
$markets = @{
  sh = "sh000001.day"
  sz = "sz399001.day"
  bj = "bj920001.day"
}

function Get-TdxLastRecordDate {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }

  $stream = [System.IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 32 -or $stream.Length % 32 -ne 0) {
      throw "Invalid TongdaXin day file: $Path"
    }
    [void]$stream.Seek(-32, [System.IO.SeekOrigin]::End)
    $bytes = New-Object byte[] 4
    if ($stream.Read($bytes, 0, 4) -ne 4) {
      throw "Could not read the final TongdaXin record: $Path"
    }
    $encoded = [System.BitConverter]::ToInt32($bytes, 0).ToString()
    return [datetime]::ParseExact($encoded, "yyyyMMdd", [Globalization.CultureInfo]::InvariantCulture).Date
  } finally {
    $stream.Dispose()
  }
}

function Get-MarketDates {
  param([Parameter(Mandatory)][string]$Root)

  $dates = @{}
  foreach ($market in $markets.Keys) {
    $sample = Join-Path $Root "$market\lday\$($markets[$market])"
    $dates[$market] = Get-TdxLastRecordDate -Path $sample
  }
  return $dates
}

function Format-MarketDates {
  param([Parameter(Mandatory)][hashtable]$Dates)

  return ($markets.Keys | Sort-Object | ForEach-Object {
    $value = $Dates[$_]
    "${_}=$(if ($value) { $value.ToString('yyyy-MM-dd') } else { 'missing' })"
  }) -join ", "
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null

$metadataUrl = "$MetadataUri$(if ($MetadataUri.Query) { '&' } else { '?' })t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$metadata = (Invoke-WebRequest -Uri $metadataUrl -UseBasicParsing -TimeoutSec 30).Content
$match = [regex]::Match($metadata, 'HSJDAY_SOFT_TIME="(?<timestamp>[^"]+)"')
if (-not $match.Success) {
  throw "TongdaXin metadata did not contain HSJDAY_SOFT_TIME"
}
$remoteDate = [datetime]::ParseExact(
  $match.Groups["timestamp"].Value,
  "yyyy-MM-dd HH:mm:ss",
  [Globalization.CultureInfo]::InvariantCulture
).Date

$currentDates = Get-MarketDates -Root $dataRoot
Write-Output "TongdaXin source: $(Format-MarketDates -Dates $currentDates); official=$($remoteDate.ToString('yyyy-MM-dd'))"
$needsUpdate = $markets.Keys | Where-Object { -not $currentDates[$_] -or $currentDates[$_] -lt $remoteDate }
if (-not $needsUpdate) {
  Write-Output "TongdaXin data is already current."
  exit 0
}

Write-Output "Downloading official TongdaXin day archive..."
if (Test-Path -LiteralPath $partialArchive) {
  Remove-Item -LiteralPath $partialArchive -Force
}
Invoke-WebRequest -Uri $ArchiveUri -OutFile $partialArchive -UseBasicParsing -TimeoutSec 1800
if ((Get-Item -LiteralPath $partialArchive).Length -lt 1MB) {
  throw "Downloaded TongdaXin archive is unexpectedly small"
}
Move-Item -LiteralPath $partialArchive -Destination $archive -Force

$entries = @(& tar -tf $archive)
if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
  throw "TongdaXin archive could not be read"
}
$unsafe = $entries | Where-Object {
  $_ -match '(^|/)\.\.(/|$)' -or
  $_ -match '^[\\/]' -or
  $_ -match '^[A-Za-z]:' -or
  $_ -notmatch '^(sh|sz|bj)/lday/'
}
if ($unsafe) {
  throw "TongdaXin archive contains an unexpected path: $($unsafe[0])"
}
foreach ($market in $markets.Keys) {
  $expected = "$market/lday/$($markets[$market])"
  if ($entries -notcontains $expected) {
    throw "TongdaXin archive is missing required sample: $expected"
  }
}

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
  & tar -xf $archive -C $staging
  if ($LASTEXITCODE -ne 0) {
    throw "TongdaXin archive extraction failed"
  }

  $stagedDates = Get-MarketDates -Root $staging
  foreach ($market in $markets.Keys) {
    if ($stagedDates[$market] -ne $remoteDate) {
      $actual = if ($stagedDates[$market]) { $stagedDates[$market].ToString("yyyy-MM-dd") } else { "missing" }
      throw "TongdaXin $market sample date is $actual; expected $($remoteDate.ToString('yyyy-MM-dd'))"
    }
  }
  Write-Output "Verified archive dates: $(Format-MarketDates -Dates $stagedDates)"

  foreach ($market in $markets.Keys) {
    $source = Join-Path $staging $market
    $destination = Join-Path $dataRoot $market
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    & robocopy $source $destination /E /R:2 /W:2 /MT:16 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
      throw "TongdaXin $market synchronization failed with robocopy exit code $LASTEXITCODE"
    }
  }

  $finalDates = Get-MarketDates -Root $dataRoot
  foreach ($market in $markets.Keys) {
    if ($finalDates[$market] -ne $remoteDate) {
      throw "TongdaXin $market data failed final verification"
    }
  }
  Write-Output "TongdaXin update complete: $(Format-MarketDates -Dates $finalDates)"
} finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
  }
}

exit 0
