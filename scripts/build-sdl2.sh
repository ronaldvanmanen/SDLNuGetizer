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

MakeDirectory builds downloads artifacts artifacts/bin

pushd downloads/
wget https://github.com/libsdl-org/SDL/releases/download/release-2.26.5/SDL2-2.26.5.tar.gz
tar -vxzf SDL2-2.26.5.tar.gz 
rm -f SDL2-2.26.5.tar.gz 
popd

sudo apt-get update
sudo apt-get -y install build-essential git make \
pkg-config cmake ninja-build gnome-desktop-testing libasound2-dev libpulse-dev \
libaudio-dev libjack-dev libsndio-dev libx11-dev libxext-dev \
libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev \
libxkbcommon-dev libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev \
libegl1-mesa-dev libdbus-1-dev libibus-1.0-dev libudev-dev fcitx-libs-dev

cmake -S ./downloads/SDL2-2.26.5 -B ./builds/SDL2-2.26.5 -DCMAKE_BUILD_TYPE=Release
cmake --build ./builds/SDL2-2.26.5 --config Release
cmake --install ./builds/SDL2-2.26.5 --prefix ./artifacts/bin/SDL2-2.26.5

popd