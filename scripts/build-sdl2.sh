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

architecture=''

while [[ $# -gt 0 ]]; do
  lower="$(echo "$1" | awk '{print tolower($0)}')"
  case $lower in
    --architecture)
      architecture=$2
      shift 2
      ;;
    *)
      properties="$properties $1"
      shift 1
      ;;
  esac
done

if [[ -z "$architecture" ]]; then
  architecture="<auto>"
fi

RepoRoot="$ScriptRoot/.."

ArtifactsRoot="$RepoRoot/artifacts"
BuildRoot="$ArtifactsRoot/build"
SourceRoot="$ArtifactsRoot/src"
InstallRoot="$ArtifactsRoot/bin"
PackageRoot="$ArtifactsRoot/pkg"

MakeDirectory "$ArtifactsRoot" "$BuildRoot" "$SourceRoot" "$InstallRoot" "$PackageRoot"

if [[ ! -z "$architecture" ]]; then
  echo "$ScriptName: Installing dotnet ..."
  export DOTNET_CLI_TELEMETRY_OPTOUT=1
  export DOTNET_MULTILEVEL_LOOKUP=0
  export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

  DotNetInstallScript="$ArtifactsRoot/dotnet-install.sh"
  wget -O "$DotNetInstallScript" "https://dot.net/v1/dotnet-install.sh"

  DotNetInstallDirectory="$ArtifactsRoot/dotnet"
  MakeDirectory "$DotNetInstallDirectory"

  bash "$DotNetInstallScript" --channel 6.0 --version latest --install-dir "$DotNetInstallDirectory" --architecture "$architecture"
  LAST_EXITCODE=$?
  if [ $LAST_EXITCODE != 0 ]; then
    echo "$ScriptName: Failed to install dotnet."
    exit "$LAST_EXITCODE"
  fi

  PATH="$DotNetInstallDirectory:$PATH:"
fi

echo "$ScriptName: Restoring dotnet tools ..."
dotnet tool restore
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to restore dotnet tools."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Determine which SDL2 version to download and build..."
MajorMinorPatch=$(dotnet gitversion /output json /showvariable MajorMinorPatch)
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to determine which SDL2 version to download and build."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Determine version for SDL2 NuGet package..."
NuGetVersion=$(dotnet gitversion /output json /showvariable NuGetVersion)
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to determine version for SDL2 NuGet package."
  exit "$LAST_EXITCODE"
fi

pushd $SourceRoot

if [ ! -f "SDL2-$MajorMinorPatch.tar.gz" ]
then
  DownloadUrl="https://github.com/libsdl-org/SDL/releases/download/release-$MajorMinorPatch/SDL2-$MajorMinorPatch.tar.gz"
  echo "$ScriptName: Downloading SDL2 $MajorMinorPatch from $DownloadUrl..."
  wget "$DownloadUrl"
  LAST_EXITCODE=$?
  if [ $LAST_EXITCODE != 0 ]; then
    echo "$ScriptName: Failed to download SDL2 $MajorMinorPatch from $ArchiveUrl."
    exit "$LAST_EXITCODE"
  fi
fi

echo "$ScriptName: Extracting SDL2 $MajorMinorPatch from $DownloadUrl..."
tar -vxzf SDL2-$MajorMinorPatch.tar.gz 
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to download SDL2 version $MajorMinorPatch."
  exit "$LAST_EXITCODE"
fi

popd

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

SourceDir="$SourceRoot/SDL2-$MajorMinorPatch"
BuildDir="$BuildRoot/SDL2-$MajorMinorPatch"
InstallDir="$InstallRoot/SDL2-$MajorMinorPatch"

echo "$ScriptName: Setting up build for SDL2 $MajorMinorPatch in $BuildDir..."
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
  echo "$ScriptName: Failed to setup build for SDL2 $MajorMinorPatch in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Building SDL2 $MajorMinorPatch in $BuildDir..."
cmake --build "$BuildDir" --config Release
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to build SDL2 $MajorMinorPatch in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Installing SDL2 $MajorMinorPatch to $InstallDir..."
cmake --install "$BuildDir" --prefix "$InstallDir"
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install SDL2 version $MajorMinorPatch in $InstallDir."
  exit "$LAST_EXITCODE"
fi

RuntimeIdentifier='linux-x64'

PackageName="SDL2.runtime.$RuntimeIdentifier"

echo "$ScriptName: Producing package folder structure for SDL2 $MajorMinorPatch ..."
PackageBuildDir="$BuildRoot/$PackageName"
MakeDirectory "$PackageBuildDir"
cp -dR "$RepoRoot/packages/$PackageName/." "$PackageBuildDir"
cp -d "$SourceDir/LICENSE.txt" "$PackageBuildDir"
cp -d "$SourceDir/README.md" "$PackageBuildDir"
cp -d "$SourceDir/README-SDL.txt" "$PackageBuildDir"
cp -d "$SourceDir/VERSION.txt" "$PackageBuildDir"

PackageRuntimeDir="$PackageBuildDir/runtimes/$RuntimeIdentifier/native"
MakeDirectory "$PackageRuntimeDir"
cp -d "$InstallDir/lib/libSDL2"*"so"* "$PackageRuntimeDir"

echo "$ScriptName: Packing SDL2 $MajorMinorPatch versioned as $NuGetVersion..."
nuget pack "$PackageBuildDir/SDL2.runtime.linux-x64.nuspec" -Properties "version=$NuGetVersion" -OutputDirectory $PackageRoot
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to pack SDL2 $MajorMinorPatch."
  exit "$LAST_EXITCODE"
fi
