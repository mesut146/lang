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