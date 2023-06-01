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

MakeDirectory "$ArtifactsRoot" "$BuildRoot" "$SourceRoot" "$InstallRoot"

if [[ ! -z "$architecture" ]]; then
  export DOTNET_CLI_TELEMETRY_OPTOUT=1
  export DOTNET_MULTILEVEL_LOOKUP=0
  export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

  DotNetInstallScript="$ArtifactsRoot/dotnet-install.sh"
  wget -O "$DotNetInstallScript" "https://dot.net/v1/dotnet-install.sh"

  DotNetInstallDirectory="$ArtifactsRoot/dotnet"
  MakeDirectory "$DotNetInstallDirectory"

  bash "$DotNetInstallScript" --channel 6.0 --version latest --install-dir "$DotNetInstallDirectory" --architecture "$architecture"

  PATH="$DotNetInstallDirectory:$PATH:"
fi

dotnet tool restore

GitVersion=$(dotnet gitversion /output json /showvariable MajorMinorPatch)
LAST_EXITCODE = $?
if [ $LAST_EXITCODE != 0 ]; then
  echo "dotnet gitversion failed"
  exit $LAST_EXITCODE
fi

pushd $SourceRoot
wget "https://github.com/libsdl-org/SDL/releases/download/release-$GitVersion/SDL2-$GitVersion.tar.gz"
LAST_EXITCODE = $?
if [ $LAST_EXITCODE != 0 ]; then
  echo "Download SDL2-$GitVersion.tar.gz failed"
  exit $LAST_EXITCODE
fi
tar -vxzf SDL2-$GitVersion.tar.gz 
rm -f SDL2-$GitVersion.tar.gz 
popd

sudo apt-get update
sudo apt-get -y install build-essential git make \
pkg-config cmake ninja-build gnome-desktop-testing libasound2-dev libpulse-dev \
libaudio-dev libjack-dev libsndio-dev libx11-dev libxext-dev \
libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev \
libxkbcommon-dev libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev \
libegl1-mesa-dev libdbus-1-dev libibus-1.0-dev libudev-dev fcitx-libs-dev \
libpipewire-0.3-dev libwayland-dev libdecor-0-dev

SourceDir="$SourceRoot/SDL2-$GitVersion"
BuildDir="$BuildRoot/SDL2-$GitVersion"
InstallDir="$InstallRoot/SDL2-$GitVersion"

cmake -S "$SourceDir" -B "$BuildDir" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BuildDir" --config Release
cmake --install "$BuildDir" --prefix "$InstallDir"
