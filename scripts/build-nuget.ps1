Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function New-Directory([string[]] $Path) {
  if (!(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force -ItemType "Directory" | Out-Null
  }
}

function Copy-File([string[]] $Path, [string] $Destination, [switch] $Force, [switch] $Recurse) {
  if (!(Test-Path -Path $Destination)) {
    New-Item -Path $Destination -Force:$Force -ItemType "Directory" | Out-Null
  }
  Copy-Item -Path $Path -Destination $Destination -Force:$Force -Recurse:$Recurse
}

try {
  $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

  $ArtifactsRoot = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsRoot

  $SourceRoot = Join-Path -Path $ArtifactsRoot -ChildPath "src"
  New-Directory -Path $SourceRoot

  $InstallRoot = Join-Path -Path $ArtifactsRoot -ChildPath "bin"
  New-Directory -Path $InstallRoot

  $PackageRoot = Join-Path $ArtifactsRoot -ChildPath "pkg"
  New-Directory -Path $PackageRoot

  $DotNetInstallScriptUri = "https://dot.net/v1/dotnet-install.ps1"
  Write-Host "${ScriptName}: Downloading dotnet-install.ps1 script from $DotNetInstallScriptUri..." -ForegroundColor Yellow
  $DotNetInstallScript = Join-Path -Path $ArtifactsRoot -ChildPath "dotnet-install.ps1"
  Invoke-WebRequest -Uri $DotNetInstallScriptUri -OutFile $DotNetInstallScript -UseBasicParsing

  Write-Host "${ScriptName}: Installing dotnet 6.0..." -ForegroundColor Yellow
  $DotNetInstallDirectory = Join-Path -Path $ArtifactsRoot -ChildPath "dotnet"
  New-Directory -Path $DotNetInstallDirectory

  $env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
  $env:DOTNET_MULTILEVEL_LOOKUP = 0
  $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 1

  # & $DotNetInstallScript -Channel 6.0 -Version latest -InstallDir $DotNetInstallDirectory

  $env:PATH="$DotNetInstallDirectory;$env:PATH"

  Write-Host "${ScriptName}: Restoring dotnet tools..." -ForegroundColor Yellow
  & dotnet tool restore
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed restore dotnet tools."
  }

  Write-Host "${ScriptName}: Determine which SDL2 version to download, build, and pack..." -ForegroundColor Yellow
  $GitVersion = dotnet gitversion /output json | ConvertFrom-Json
  $MajorMinorPatch = $GitVersion.MajorMinorPatch
  $NuGetVersion = $GitVersion.NuGetVersion

  Push-Location $SourceRoot

  $BaseName = "SDL2-$MajorMinorPatch"

  $ArchiveFileName = "$BaseName.zip"
  if (!(Test-Path "$ArchiveFileName")) {
    $DownloadUrl = "https://github.com/libsdl-org/SDL/releases/download/release-$MajorMinorPatch/$ArchiveFileName"
    Write-Host "${ScriptName}: Downloading SDL2 $MajorMinorPatch from $DownloadUrl..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchiveFileName
    if ($LastExitCode -ne 0) {
      throw "${ScriptName}: Failed to download SDL2 $MajorMinorPatch from $DownloadUrl."
    }
  }

  Write-Host "${ScriptName}: Extracting SDL2 $MajorMinorPatch to $SourceRoot..." -ForegroundColor Yellow
  Expand-Archive -Path $ArchiveFileName -DestinationPath $SourceRoot -Force *>&1
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to extract SDL2 $MajorMinorPatch to $SourceRoot."
  }

  Pop-Location

  Write-Host "${ScriptName}: Producing package folder structure for SDL2 $MajorMinorPatch..." -ForegroundColor Yellow
  $SourceDir = Join-Path -Path $SourceRoot -ChildPath $BaseName
  $PackageName="SDL2"
  $PackDir = Join-Path -Path $PackageRoot -ChildPath $PackageName

  Copy-File -Path "$RepoRoot\packages\$PackageName\*" -Destination $PackDir -Force -Recurse
  Copy-File -Path "$SourceDir\BUGS.txt" $PackDir
  Copy-File -Path "$SourceDir\LICENSE.txt" $PackDir
  Copy-File -Path "$SourceDir\README.md" $PackDir
  Copy-File -Path "$SourceDir\README-SDL.txt" $PackDir
  Copy-File -Path "$SourceDir\VERSION.txt" $PackDir
  Copy-File -Path "$SourceDir\WhatsNew.txt" $PackDir
  Copy-File -Path "$SourceDir\docs\*.md" $PackDir\docs
  Copy-File -Path "$SourceDir\include\*.h" $PackDir\lib\native\include

  Write-Host "${ScriptName}: Replacing variable `$version`$ in runtime.json with value '$NuGetVersion'..." -ForegroundColor Yellow
  $RuntimeContent = Get-Content $PackDir\runtime.json -Raw
  $RuntimeContent = $RuntimeContent.replace('$version$', $NuGetVersion)
  Set-Content $PackDir\runtime.json $RuntimeContent

  Write-Host "${ScriptName}: Building package from SDL2.nuspec..." -ForegroundColor Yellow
  & nuget pack $PackDir\SDL2.nuspec -Properties version=$NuGetVersion -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to pack SDL2 package."
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
