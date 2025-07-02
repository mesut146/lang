
if [ ! -f "$1" ]; then
  echo "provide compiler binary \$1"
  exit
fi

if [ ! -d "$2" ]; then
  echo "provide old toolchain dir \$2"
  exit
fi

if [ ! -d "$3" ]; then
  echo "provide output dir \$3"
  exit
fi

if [ -z "$4" ]; then
  echo "enter version \$4"
  exit
fi

is_zip=false

if [ "$5" = "-zip" ]; then
  is_zip=true
fi

cur=$(dirname $0)

binary="$1"
old_toolchain="$2"
out_dir="$3"
version="$4"
arch=$ARCH

if [ -z $ARCH ]; then
  arch=$(uname -m)
fi
name="x-toolchain-${version}-${arch}"
dir=$out_dir/$name

mkdir -p $dir
mkdir -p $dir/bin
mkdir -p $dir/lib
mkdir -p $dir/src

cp $binary $dir/bin/x
cp $old_toolchain/lib/libbridge.so $dir/lib
cp $old_toolchain/lib/libbridge.a $dir/lib
cp $old_toolchain/lib/libLLVM.so.19.1 $dir/lib
cp $(dirname $binary)/std_out/std.a $dir/lib
cp -r $cur/../src/std $dir/src

sudo=""
if command -v sudo 2>&1 >/dev/null; then
  sudo="sudo"
fi
#change llvm path to relative to toolchain
if ! command -v patchelf 2>&1 >/dev/null; then
  $sudo apt install -y patchelf
fi

patchelf --set-rpath '$ORIGIN/../lib' $dir/bin/x

if [ $is_zip = true ]; then
  cd $out_dir
  zip -r ${name}.zip "./$name" && echo "built toolchain ${name}.zip"
else
  echo "built toolchain ${name}/"
fi
