sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

if [ -z "${XTMP:-}" ]; then
  echo "Error: XTMP environment variable is not set" >&2
  exit 1
fi

# NOTE (termux): Debian arm64 libLLVM/libz3 binaries are NOT usable for
# Android linking (libLLVM comes from the previous Termux toolchain instead),
# but we still need llvm-19-dev headers to compile cpp_bridge with the NDK.
# Headers are arch-independent, so use the native amd64 deb (this mirror has
# no arm64 Packages files).
if [ ! -z "$XTERMUX" ]; then
  if [ ! -f $XTMP/llvm-19-dev*.deb ]; then
    if ! grep -Rq "apt.llvm.org/noble" /etc/apt/sources.list /etc/apt/sources.list.d/; then
      sudo mkdir -p /etc/apt/keyrings
      wget -qO /etc/apt/keyrings/llvm.asc https://apt.llvm.org/llvm-snapshot.gpg.key
      echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] http://apt.llvm.org/noble/ llvm-toolchain-noble main" | \
      sudo tee /etc/apt/sources.list.d/llvm.list
    fi
    mkdir -p $XTMP
    pushd $XTMP
    sudo apt-get update
    sudo apt-get download llvm-19-dev
    dpkg-deb -x ./llvm-19-dev*.deb .
    popd
  fi
  exit 0
fi

if [ ! -f $XTMP/llvm-19-dev*.deb ]; then

    if ! grep -Rq "apt.llvm.org/noble" /etc/apt/sources.list /etc/apt/sources.list.d/; then
      sudo mkdir -p /etc/apt/keyrings
      wget -qO /etc/apt/keyrings/llvm.asc https://apt.llvm.org/llvm-snapshot.gpg.key
      echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] http://apt.llvm.org/noble/ llvm-toolchain-noble main" | \
      sudo tee /etc/apt/sources.list.d/llvm.list
    fi


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
