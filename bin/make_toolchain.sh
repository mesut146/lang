if [ ! -f "$1" ]; then
  echo "enter binary"
  exit
fi

if [ ! -d "$2" ]; then
  echo "enter old toolchain"
  exit
fi

if [ ! -d "$3" ]; then
  echo "enter output dir"
  exit
fi

cur=$(dirname $0)

version=""
#version="-1.0"
binary="$1"
old_toolchain="$2"
out="$3"
name="x-toolchain${version}-$(uname -m)"
dir=$out/$name

mkdir -p $dir
mkdir -p $dir/bin
mkdir -p $dir/lib
mkdir -p $dir/src

cp $binary $dir/bin/x
cp $old_toolchain/lib/libbridge.so $dir/lib
cp $old_toolchain/lib/libbridge.a $dir/lib
cp $old_toolchain/lib/libLLVM.so $dir/lib
cp -r $cur/../src/std $dir/src

if [ "$4" = "-zip" ]; then
 zip -r ${name}.zip $dir
 rm -r $dir
fi
