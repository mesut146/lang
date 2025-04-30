if [ ! -f "$1" ]; then
  echo "enter binary"
  exit
fi

if [ ! -d "$2" ]; then
  echo "enter output dir"
  exit
fi

bin="$1"
out="$2"
dir=$out/x-toolchain-x64

mkdir -p $dir
mkdir -p $dir/bin
mkdir -p $dir/lib
mkdir -p $dir/src

cp $bin $dir/bin/x
cp ../cpp_bridge/build/libbridge.so $dir/lib
cp ../cpp_bridge/build/libbridge.a $dir/lib
#todo llvm
cp /usr/lib/llvm-19/lib/libLLVM.so $dir/lib
cp -r ../src/std $dir/src
