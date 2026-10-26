#!/bin/bash

dir=$(dirname $0)

sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

#XENV_READY is set by the cross-build image (bin/Dockerfile): the packages are
#already installed there, so only the parts that need the checkout (the NDK) run
#again at container start.
if [ -z "$XENV_READY" ]; then
sudo dpkg --add-architecture arm64
sudo apt-get update
sudo apt-get install -y zip unzip libffi8 libedit2 libzstd1 libxml2
sudo apt-get install -y --only-upgrade libstdc++6
sudo apt-get install -y binutils g++-aarch64-linux-gnu libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2-16:arm64
sudo apt-get install -y wget software-properties-common gnupg
fi


if [ ! -z "$XTERMUX" ]; then
  #The NDK is arch-independent and only the termux build needs it, so it is not
  #part of the cross-build image (a 2.5GB layer to export per run); this fetch
  #runs at container start. NDK_ROOT lets a caller keep it elsewhere.
  NDK_ROOT="${NDK_ROOT:-android-ndk-r27c}"
  ndk_clang="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
  if [ ! -x "$ndk_clang" ]; then
    #the zip's top dir is android-ndk-r27c: unpack next to the target name
    ndk_parent=$(dirname "$NDK_ROOT")
    mkdir -p "$ndk_parent"
    ( cd "$ndk_parent" \
      && wget -q "https://dl.google.com/android/repository/android-ndk-r27c-linux.zip" \
      && unzip -q android-ndk-r27c-linux.zip \
      && rm -f android-ndk-r27c-linux.zip )
  fi
  export LD="$ndk_clang"
fi
