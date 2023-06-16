<#
  .SYNOPSIS
  Builds Windows native NuGet package for SDL2.

  .DESCRIPTION
  Builds Windows native NuGet package for SDL2.

  .PARAMETER runtime
  The runtime identifier to use for the native package (e.g. win-x64, win-x86).

  .INPUTS
  None.

  .OUTPUTS
  None.

  .EXAMPLE
  PS> .\build-sdl2 -architecture x64

  .EXAMPLE
  PS> .\build-sdl2 -architecture x86
#>

[CmdletBinding(PositionalBinding=$false)]
Param(
  [Parameter(Mandatory)][ValidateSet("x64", "x86")][string] $architecture = ""
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

  Write-Host "${ScriptName}: Calculating SDL2 package version..." -ForegroundColor Yellow
  $PackageVersion = dotnet gitversion /showvariable NuGetVersion /output json
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed calculate SDL2 package version."
  }

  $SourceDir = Join-Path -Path $SourceRoot -ChildPath "SDL"
  $BuildDir = Join-Path -Path $BuildRoot -ChildPath "SDL2"
  $InstallDir = Join-Path -Path $InstallRoot -ChildPath "SDL2"
  $PlatformFlags = ""
  
  switch ($architecture) {
    "x64" { $PlatformFlags = "-A x64" }
    "x86" { $PlatformFlags = "-A Win32"}
  }

  Write-Host "${ScriptName}: Generating build system for SDL2 in $BuildDir..." -ForegroundColor Yellow
  & cmake -S $SourceDir -B $BuildDir -DSDL_INSTALL_TESTS=OFF -DSDL_TESTS=OFF -DSDL_WERROR=ON -DSDL_SHARED=ON -DSDL_STATIC=OFF -DCMAKE_BUILD_TYPE=Release $PlatformFlags
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

  $Runtime = "win-${architecture}"
  $RuntimePackageName = "SDL2.runtime.$Runtime"
  $RuntimePackageBuildDir = Join-Path -Path $PackageRoot -ChildPath $RuntimePackageName
  $DevelPackageName = "SDL2.devel.$Runtime"
  $DevelPackageBuildDir = Join-Path -Path $PackageRoot -ChildPath $DevelPackageName

  Write-Host "${ScriptName}: Producing SDL2 runtime package folder structure in $RuntimePackageBuildDir..." -ForegroundColor Yellow
  Copy-File -Path "$RepoRoot\packages\$RuntimePackageName\*" -Destination $RuntimePackageBuildDir -Force -Recurse
  Copy-File -Path "$SourceDir\LICENSE.txt" $RuntimePackageBuildDir -Force
  Copy-File -Path "$SourceDir\README-SDL.txt" $RuntimePackageBuildDir -Force
  Copy-File -Path "$InstallDir\bin\*.dll" "$RuntimePackageBuildDir\runtimes\$Runtime\native" -Force

  Write-Host "${ScriptName}: Building SDL2 runtime package..." -ForegroundColor Yellow
  & nuget pack $RuntimePackageBuildDir\$RuntimePackageName.nuspec -Properties version=$PackageVersion -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2 runtime package."
  }

  Write-Host "${ScriptName}: Producing SDL2 development package folder structure in $DevelPackageBuildDir..." -ForegroundColor Yellow
  Copy-File -Path "$RepoRoot\packages\$DevelPackageName\*" -Destination $DevelPackageBuildDir -Force -Recurse
  Copy-File -Path "$SourceDir\BUGS.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\LICENSE.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\README-SDL.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\README.md" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\WhatsNew.txt" $DevelPackageBuildDir -Force
  Copy-File -Path "$SourceDir\docs\*" "$DevelPackageBuildDir\docs" -Force
  Copy-File -Path "$InstallDir\cmake\*" "$DevelPackageBuildDir\cmake" -Force
  Copy-File -Path "$InstallDir\include\SDL2\*" "$DevelPackageBuildDir\include" -Force
  Copy-File -Path "$InstallDir\bin\*.dll" "$DevelPackageBuildDir\lib\$architecture" -Force
  Copy-File -Path "$InstallDir\lib\*.lib" "$DevelPackageBuildDir\lib\$architecture" -Force

  Write-Host "${ScriptName}: Building SDL2 development package..." -ForegroundColor Yellow
  & nuget pack $DevelPackageBuildDir\$DevelPackageName.nuspec -Properties "version=$PackageVersion;NoWarn=NU5103,NU5128" -OutputDirectory $PackageRoot
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to build SDL2 development package."
  }
}
catch {
  Write-Host -Object $_ -ForegroundColor Red
  Write-Host -Object $_.Exception -ForegroundColor Red
  Write-Host -Object $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
