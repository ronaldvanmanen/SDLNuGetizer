[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("win-x64", "win-x86")][string] $runtime = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function New-Directory([string[]] $Path) {
  if (!(Test-Path -Path $Path)) {
    New-Item -Path $Path -Force -ItemType "Directory" | Out-Null
  }
}

try {
  $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."

  $ArtifactsRoot = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsRoot

  $BuildRoot = Join-Path -Path $ArtifactsRoot -ChildPath "build"
  New-Directory -Path $BuildRoot

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

  $ArchiveFileName = "SDL2-$MajorMinorPatch.zip"
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

  $BaseName = "SDL2-$MajorMinorPatch"
  $SourceDir = Join-Path -Path $SourceRoot -ChildPath $BaseName
  $BuildDir = Join-Path -Path $BuildRoot -ChildPath $BaseName
  $InstallDir = Join-Path -Path $InstallRoot -ChildPath $BaseName

  Write-Host "${ScriptName}: Generating build system for SDL2 $MajorMinorPatch in $BuildDir..." -ForegroundColor Yellow
  & cmake -S $SourceDir -B $BuildDir -DSDL2_DISABLE_SDL2MAIN=ON -DSDL_INSTALL_TESTS=OFF -DSDL_TESTS=OFF -DSDL_WERROR=ON -DSDL_SHARED=ON -DSDL_STATIC=OFF -DCMAKE_BUILD_TYPE=Release
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to generate build system for SDL2 $MajorMinorPatch in $BuildDir."
  }

  Write-Host "${ScriptName}: Building SDL2 $MajorMinorPatch in $BuildDir..." -ForegroundColor Yellow
  & cmake --build $BuildDir --config Release
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2 $MajorMinorPatch in $BuildDir."
  }

  Write-Host "${ScriptName}: Installing SDL2 $MajorMinorPatch in $InstallDir..." -ForegroundColor Yellow
  & cmake --install $BuildDir --prefix $InstallDir
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to install SDL2 $MajorMinorPatch in $InstallDir."
  }

  Write-Host "${ScriptName}: Producing package folder structure for SDL2 $MajorMinorPatch..." -ForegroundColor Yellow
  $PackageName="SDL2.runtime.$runtime"
  $PackageBuildDir = Join-Path -Path $BuildRoot -ChildPath $PackageName
  Copy-Item -Path "$RepoRoot\packages\$PackageName\." -Destination $PackageBuildDir -Force -Recurse
  Copy-Item -Path "$SourceDir\LICENSE.txt" $PackageBuildDir
  Copy-Item -Path "$SourceDir\README.md" $PackageBuildDir
  Copy-Item -Path "$SourceDir\README-SDL.txt" $PackageBuildDir
  Copy-Item -Path "$SourceDir\VERSION.txt" $PackageBuildDir
  
  $PackageRuntimeDir="$PackageBuildDir\runtimes\$runtime\native"
  New-Directory "$PackageRuntimeDir"
  Copy-Item -Path "$InstallDir\bin\*.dll" "$PackageRuntimeDir"

  Write-Host "${ScriptName}: Packing SDL2 $MajorMinorPatch (versioned $NuGetVersion)..." -ForegroundColor Yellow
  & nuget pack $PackageBuildDir\$PackageName.nuspec -Properties version=$NuGetVersion -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to pack SDL2 $MajorMinorPatch (versioned $NuGetVersion)."
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
