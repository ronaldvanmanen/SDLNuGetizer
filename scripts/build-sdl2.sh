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

RepoRoot="$ScriptRoot/.."

pushd $RepoRoot

ArtifactsDir="$RepoRoot/artifacts"
BuildDir="$ArtifactsDir/build"
DownloadDir="$ArtifactsDir/downloads"
BinDir="$ArtifactsDir/bin"

MakeDirectory "$ArtifactsDir" "$BuildDir" "$DownloadDir" "$BinDir"

if [[ -z "$architecture" ]]; then
  architecture="<auto>"
fi

if [[ ! -z "$architecture" ]]; then
  export DOTNET_CLI_TELEMETRY_OPTOUT=1
  export DOTNET_MULTILEVEL_LOOKUP=0
  export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

  DotNetInstallScript="$ArtifactsDir/dotnet-install.sh"
  wget -O "$DotNetInstallScript" "https://dot.net/v1/dotnet-install.sh"

  DotNetInstallDirectory="$ArtifactsDir/dotnet"
  MakeDirectory "$DotNetInstallDirectory"

  bash "$DotNetInstallScript" --channel 6.0 --version latest --install-dir "$DotNetInstallDirectory" --architecture "$architecture"

  PATH="$DotNetInstallDirectory:$PATH:"
fi

wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh

dotnet tool restore

GitVersion=$(dotnet gitversion /output json /showvariable MajorMinorPatch)
if [ "$?" != 0 ]; then
  echo "dotnet gitversion failed"
  return "$?"
fi

pushd $DownloadDir
wget "https://github.com/libsdl-org/SDL/releases/download/release-$GitVersion/SDL2-$GitVersion.tar.gz"
if [ "$?" != 0 ]; then
  echo "Download SDL2 failed"
  return "$?"
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

cmake -S "$DownloadDir/SDL2-$GitVersion" -B "$BuildDir/SDL2-$GitVersion" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BuildDir/SDL2-$GitVersion" --config Release
cmake --install "$BuildDir/SDL2-$GitVersion" --prefix "$BinDir/SDL2-$GitVersion"

popd