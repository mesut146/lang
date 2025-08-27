
if [ ! -f "$1" ]; then
  echo "provide compiler binary $1"
  exit
fi

if [ ! -d "$2" ]; then
  echo "provide output dir \$2"
  exit
fi

if [ -z "$3" ]; then
  echo "enter version \$3"
  exit
fi
if [ -z "$LIBLLVM" ]; then
  echo "missing \$LIBLLVM" && exit 1
fi

is_zip=false

if [ "$4" = "-zip" ]; then
  is_zip=true
fi

cur=$(dirname $0)

binary="$1"
out_dir="$2"
version="$3"
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
cp $LIBLLVM $dir/lib
cp $(dirname $binary)/std_out/std.a $dir/lib
if [ ! -z "$LIBZ3" ]; then
  cp $LIBZ3 $dir/lib
fi
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
