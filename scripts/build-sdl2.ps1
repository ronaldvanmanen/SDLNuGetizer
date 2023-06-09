<#
  .SYNOPSIS
  Builds Windows native NuGet package for SDL2.

  .DESCRIPTION
  Builds Windows native NuGet package for SDL2.

  .PARAMETER runtime
  The runtime identifier to use for the native package (i.e. win-x64, win-x86).

  .INPUTS
  None.

  .OUTPUTS
  None.

  .EXAMPLE
  PS> .\build-sdl2 -runtime win-x64

  .EXAMPLE
  PS> .\build-sdl2 -runtime win-x86
#>

[CmdletBinding(PositionalBinding=$false)]
Param(
  [Parameter(Mandatory)][ValidateSet("win-x64", "win-x86")][string] $runtime = ""
)

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

  $SourceRoot = Join-Path -Path $RepoRoot -ChildPath "sources"

  $ArtifactsRoot = Join-Path -Path $RepoRoot -ChildPath "artifacts"
  New-Directory -Path $ArtifactsRoot

  $BuildRoot = Join-Path -Path $ArtifactsRoot -ChildPath "build"
  New-Directory -Path $BuildRoot

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

  Write-Host "${ScriptName}: Calculating NuGet version for SDL2..." -ForegroundColor Yellow
  $NuGetVersion = dotnet gitversion /showvariable NuGetVersion /output json
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed calculate NuGet version for SDL2."
  }

  $SourceDir = Join-Path -Path $SourceRoot -ChildPath "SDL"
  $BuildDir = Join-Path -Path $BuildRoot -ChildPath "SDL2"
  $InstallDir = Join-Path -Path $InstallRoot -ChildPath "SDL2"

  Write-Host "${ScriptName}: Generating build system for SDL2 in $BuildDir..." -ForegroundColor Yellow
  & cmake -S $SourceDir -B $BuildDir -DSDL2_DISABLE_SDL2MAIN=ON -DSDL_INSTALL_TESTS=OFF -DSDL_TESTS=OFF -DSDL_WERROR=ON -DSDL_SHARED=ON -DSDL_STATIC=OFF -DCMAKE_BUILD_TYPE=Release
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to generate build system in $BuildDir."
  }

  Write-Host "${ScriptName}: Building SDL2 in $BuildDir..." -ForegroundColor Yellow
  & cmake --build $BuildDir --config Release
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2 in $BuildDir."
  }

  Write-Host "${ScriptName}: Installing SDL2 in $InstallDir..." -ForegroundColor Yellow
  & cmake --install $BuildDir --prefix $InstallDir
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to install SDL2 in $InstallDir."
  }

  $PackageName="SDL2.runtime.$runtime"
  $PackageBuildDir = Join-Path -Path $PackageRoot -ChildPath $PackageName
  Write-Host "${ScriptName}: Producing package folder structure for SDL2 in $PackageBuildDir..." -ForegroundColor Yellow
  Copy-File -Path "$RepoRoot\packages\$PackageName\*" -Destination $PackageBuildDir -Force -Recurse
  Copy-File -Path "$SourceDir\BUGS.txt" $PackageBuildDir
  Copy-File -Path "$SourceDir\LICENSE.txt" $PackageBuildDir
  Copy-File -Path "$SourceDir\README.md" $PackageBuildDir
  Copy-File -Path "$SourceDir\README-SDL.txt" $PackageBuildDir
  Copy-File -Path "$SourceDir\WhatsNew.txt" $PackageBuildDir
  Copy-File -Path "$InstallDir\bin\*.dll" "$PackageBuildDir\runtimes\$runtime\native"
  Copy-File -Path "$InstallDir\lib\*.lib" "$PackageBuildDir\lib\native"
  Copy-File -Path "$InstallDir\include\SDL2\*.h" "$PackageBuildDir\lib\native\include"

  Write-Host "${ScriptName}: Packing SDL2 (versioned $NuGetVersion)..." -ForegroundColor Yellow
  & nuget pack $PackageBuildDir\$PackageName.nuspec -Properties version=$NuGetVersion -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to pack SDL2 (versioned $NuGetVersion)."
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
