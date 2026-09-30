sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

if [ -z "${XTMP:-}" ]; then
  echo "Error: XTMP environment variable is not set" >&2
  exit 1
fi

# NOTE (termux): Debian arm64 libLLVM binaries are NOT usable for
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
      sudo apt-get download llvm-19-dev:arm64 libllvm19:arm64
      # runtime deps of arm64 libLLVM, bundled into the toolchain (see make_toolchain.sh)
      sudo apt-get download libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2-16:arm64
      # ...plus noble builds (glibc <=2.39) for devices older than sid;
      # make_toolchain.sh prefers these when present.
      if ! grep -Rq "ports.ubuntu.com.*noble" /etc/apt/sources.list /etc/apt/sources.list.d/; then
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble noble-updates main universe" | \
        sudo tee /etc/apt/sources.list.d/ubuntu-ports-noble-arm64.list
        sudo apt-get update || true
      fi
      mkdir -p ./noble-deps
      (cd ./noble-deps && sudo apt-get download libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2:arm64 || true)
    else
      #amd64
      sudo apt-get download llvm-19-dev libllvm19
    fi

    dpkg-deb -x ./llvm-19-dev*.deb .
    dpkg-deb -x ./libllvm19*.deb .
    popd
fi
