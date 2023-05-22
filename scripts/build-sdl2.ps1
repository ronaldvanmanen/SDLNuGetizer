function New-Directory([string[]] $Path) {
  if (!(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force -ItemType "Directory" | Out-Null
  }
}

function Get-GitHubRelease([string] $Owner, [string] $Repo, [string] $Tag) {
  $Uri = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
  $Headers = @{
    'Accept'='application/vnd.github+json'
    'X-GitHub-Api-Version'='2022-11-28'
  }
  Invoke-RestMethod -Headers $Headers -Uri $Uri
}
  
try {
  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

  $ArtifactsDir = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsDir

  $ArtifactsPkgDir = Join-Path $ArtifactsDir -ChildPath "pkg"
  New-Directory -Path $ArtifactsPkgDir

  $StagingDir = Join-Path -Path $RepoRoot -ChildPath "staging"
  New-Directory -Path $StagingDir

  $DownloadsDir = Join-Path -Path $RepoRoot -ChildPath "downloads"
  New-Directory -Path $DownloadsDir

  & dotnet tool restore

  $GitVersion = dotnet gitversion /output json | ConvertFrom-Json
  $MajorMinorPatch = $GitVersion.MajorMinorPatch

  Write-Host "Get SDL2 release for version $MajorMinorPatch..." -ForegroundColor Yellow
  $LatestRelease = Get-GitHubRelease -Owner 'libsdl-org' -Repo 'SDL' -Tag "release-$MajorMinorPatch"
  $LatestVersion = $LatestRelease.name
  $LatestAsset = $LatestRelease.assets | Where-Object { $_.name -Like "SDL2-$MajorMinorPatch.zip" }
  $LatestAssetName = $LatestAsset.name
  $BrowserDownloadUrl = $LatestAsset.browser_download_url

  $ZipDownloadPath = Join-Path $DownloadsDir $LatestAssetName

  if (!(Test-Path $ZipDownloadPath)) {
    Write-Host "Download SDL2 version '$LatestVersion' from '$BrowserDownloadUrl' to '$ZipDownloadPath'..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $BrowserDownloadUrl -OutFile $ZipDownloadPath
  }

  Write-Host "Extract SDL2 version '$LatestVersion' to '$DownloadsDir'..." -ForegroundColor Yellow
  Expand-Archive -Path $ZipDownloadPath -DestinationPath $DownloadsDir -Force *>&1
  
  $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($LatestAssetName)
  $SourceDir = Join-Path $DownloadsDir $BaseName
  $BuildDir = Join-Path $StagingDir $BaseName

  Write-Host "Generate build system for SDL2 version '$LatestVersion' in '$BuildDir'..." -ForegroundColor Yellow
  & cmake -S $SourceDir -B $BuildDir -DCMAKE_BUILD_TYPE=Release

  Write-Host "Build SDL2 version '$LatestVersion' in '$BuildDir'..." -ForegroundColor Yellow
  & cmake --build $BuildDir --config Release
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
