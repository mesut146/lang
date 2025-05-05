if [ ! -f "$1" ]; then
  echo "enter binary"
  exit
fi

if [ ! -d "$2" ]; then
  echo "enter output dir"
  exit
fi

cur=$(dirname $0)

binary="$1"
out="$2"
dir=$out/x-toolchain-x64

mkdir -p $dir
mkdir -p $dir/bin
mkdir -p $dir/lib
mkdir -p $dir/src

cp $binary $dir/bin/x
cp $cur/../cpp_bridge/build/libbridge.so $dir/lib
cp $cur/../cpp_bridge/build/libbridge.a $dir/lib

get_llvm(){
  wget -O libllvm.deb https://apt.llvm.org/jammy/pool/main/l/llvm-toolchain-19/libllvm19_19.1.7~%2B%2B20250114103320%2Bcd708029e0b2-1~exp1~20250114103432.75_arm64.deb
  dpkg -x libllvm.deb llvm-tmp
  mv llvm-tmp/usr/lib/aarch64-linux-gnu/libLLVM.so.19 $dir/lib
}
#todo llvm
cp /usr/lib/llvm-19/lib/libLLVM.so $dir/lib
cp -r $cur/../src/std $dir/src

if [ "$3" = "-zip" ]; then
 zip -r x-toolchain-x64.zip $dir
 rm -r $dir
fi
