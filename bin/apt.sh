#!/bin/bash

dir=$(dirname $0)

sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

sudo apt update
sudo apt-get install -y zip unzip libffi8 libedit2 libzstd1 libxml2
sudo apt-get install -y wget software-properties-common
sudo apt install -y g++ binutils

if [ ! -f $XTMP/llvm-19-dev*.deb ]; then
    sudo wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc
    sudo apt-add-repository -y "deb http://apt.llvm.org/noble/ llvm-toolchain-noble main"

    mkdir -p $XTMP
    pushd $XTMP
    echo "XCROSS=$XCROSS"
    if [ "$XCROSS" = "true" ]; then
      sudo dpkg --add-architecture arm64
      sudo apt-get download llvm-19-dev:arm64 libllvm19:arm64 libz3-4:arm64
    else
      #amd64
      sudo apt-get download llvm-19-dev libllvm19 libz3-4
    fi

    dpkg-deb -x ./llvm-19-dev*.deb .
    dpkg-deb -x ./libllvm19*.deb .
    dpkg-deb -x ./libz3-4*.deb .
    popd
fi