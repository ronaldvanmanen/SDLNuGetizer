#!/bin/bash

function MakeDirectory {
  for dirname in "$@"
  do
    if [ ! -d "$dirname" ]
    then
      mkdir -p "$dirname"
    fi
  done  
}

SOURCE="${BASH_SOURCE[0]}"

while [ -h "$SOURCE" ]; do
  # resolve $SOURCE until the file is no longer a symlink
  ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE="$ScriptRoot/$SOURCE"
done

ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

ScriptName=$(basename -s '.sh' "$SOURCE")

help=false
runtime=''

while [[ $# -gt 0 ]]; do
  lower="$(echo "$1" | awk '{print tolower($0)}')"
  case $lower in
    --help)
      help=true
      shift 1
      ;;
    --runtime)
      runtime=$2
      shift 2
      ;;
    *)
  esac
done

function Help {
  echo "  --runtime <value>         Specifies the runtime for the package (linux-x64)"
  echo "  --help                    Print help and exit"
}

if $help; then
  Help
  exit 0
fi

if [[ -z "$runtime" ]]; then
  echo "$ScriptName: runtime identifier missing."
  Help
  exit 1
fi

RepoRoot="$ScriptRoot/.."

SourceRoot="$RepoRoot/sources"

ArtifactsRoot="$RepoRoot/artifacts"
BuildRoot="$ArtifactsRoot/build"
InstallRoot="$ArtifactsRoot/bin"
PackageRoot="$ArtifactsRoot/pkg"

MakeDirectory "$ArtifactsRoot" "$BuildRoot" "$InstallRoot" "$PackageRoot"

echo "$ScriptName: Installing dotnet ..."
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_MULTILEVEL_LOOKUP=0
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

DotNetInstallScript="$ArtifactsRoot/dotnet-install.sh"
wget -O "$DotNetInstallScript" "https://dot.net/v1/dotnet-install.sh"

DotNetInstallDirectory="$ArtifactsRoot/dotnet"
MakeDirectory "$DotNetInstallDirectory"

bash "$DotNetInstallScript" --channel 6.0 --version latest --install-dir "$DotNetInstallDirectory"
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install dotnet 6.0."
  exit "$LAST_EXITCODE"
fi

PATH="$DotNetInstallDirectory:$PATH:"

echo "$ScriptName: Restoring dotnet tools ..."
dotnet tool restore
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to restore dotnet tools."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Calculating NuGet version for SDL2 version..."
NuGetVersion=$(dotnet gitversion /output json /showvariable NuGetVersion)
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to calculate NuGetVersion for SDL2."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Updating package list..."
sudo apt-get update
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to update package list."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Installing packages needed to build SDL2 $MajorMinorPatch..."
sudo apt-get -y install build-essential git make \
  pkg-config cmake ninja-build gnome-desktop-testing libasound2-dev libpulse-dev \
  libaudio-dev libjack-dev libsndio-dev libx11-dev libxext-dev \
  libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev \
  libxkbcommon-dev libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev \
  libegl1-mesa-dev libdbus-1-dev libibus-1.0-dev libudev-dev fcitx-libs-dev \
  libpipewire-0.3-dev libwayland-dev libdecor-0-dev
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install packages."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Install packages needed to package SDL2..."
sudo apt-get -y install zip mono-devel
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to update package list."
  exit "$LAST_EXITCODE"
fi

SourceDir="$SourceRoot/SDL"
BuildDir="$BuildRoot/SDL2"
InstallDir="$InstallRoot/SDL2"

echo "$ScriptName: Setting up build for SDL2 in $BuildDir..."
cmake -S "$SourceDir" -B "$BuildDir" -G Ninja \
  -DSDL2_DISABLE_SDL2MAIN=ON \
  -DSDL_INSTALL_TESTS=OFF \
  -DSDL_TESTS=OFF \
  -DSDL_WERROR=ON \
  -DSDL_SHARED=ON \
  -DSDL_STATIC=OFF \
  -DCMAKE_BUILD_TYPE=Release
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to setup build for SDL2 in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Building SDL2 in $BuildDir..."
cmake --build "$BuildDir" --config Release
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to build SDL2 in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Installing SDL2 to $InstallDir..."
cmake --install "$BuildDir" --prefix "$InstallDir"
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install SDL2 version in $InstallDir."
  exit "$LAST_EXITCODE"
fi

PackageName="SDL2.runtime.$runtime"
PackageBuildDir="$PackageRoot/$PackageName"

echo "$ScriptName: Producing package folder structure for SDL2 in $PackageBuildDir..."
MakeDirectory "$PackageBuildDir"
cp -dR "$RepoRoot/packages/$PackageName/." "$PackageBuildDir"
cp -d "$SourceDir/LICENSE.txt" "$PackageBuildDir"
cp -d "$SourceDir/README.md" "$PackageBuildDir"
cp -d "$SourceDir/README-SDL.txt" "$PackageBuildDir"
mkdir -p "$PackageBuildDir/runtimes/$runtime/native" && cp -d "$InstallDir/lib/libSDL2"*"so"* $_
mkdir -p "$PackageBuildDir/lib/native/include" && cp -d "$InstallDir/include/SDL2/"*".h" $_

NuGetCliVersion=$(nuget ? | grep -oP 'NuGet Version: \K.+')
echo "$ScriptName: Packing SDL2 versioned as $NuGetVersion (using NuGet $NuGetCliVersion)..."
nuget pack "$PackageBuildDir/SDL2.runtime.linux-x64.nuspec" -Properties "version=$NuGetVersion" -OutputDirectory $PackageRoot
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to pack SDL2 $MajorMinorPatch."
  exit "$LAST_EXITCODE"
fi
