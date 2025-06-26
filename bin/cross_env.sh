dir=$(dirname $0)

sudo=""
if command -v sudo 2>&1 >/dev/null; then
  sudo="sudo"
fi
$sudo dpkg --add-architecture arm64
$sudo apt-get update
$sudo apt-get install -y zip unzip libffi8 libedit2 libzstd1 libxml2
$sudo apt-get install -y --only-upgrade libstdc++6
$sudo apt-get install -y binutils g++-aarch64-linux-gnu libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2:arm64

if [ "$4" = "-termux" ]; then
  $sudo apt-get install -y wget
  wget "https://dl.google.com/android/repository/android-ndk-r27c-linux.zip"
  unzip "android-ndk-r27c-linux.zip"
  export LD="./android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
fi
