dir=$(dirname $0)

echo "$1,$2"
pwd
ls
ls $1
ls $2

if [ -z "$1" ]; then
 echo "provide host toolchain dir"
 exit
fi

if [ ! -d "$2" ]; then
 echo "provide target toolchain dir"
 exit
fi

toolchain=$1
toolchain_target=$2
compiler="$toolchain/bin/x"
build=$dir/../build
name="x_arm64"
out_dir=$build/${name}_out

sudo dpkg --add-architecture arm64
sudo apt update
sudo apt install -y g++-13-aarch64-linux-gnu libffi8:arm64 libedit2:arm64 libzstd1:arm64 libxml2:arm64

target_triple="aarch64-linux-gnu" $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi
#todo use toolchain's std dir?
#linker=$($dir/find_llvm.sh clang)
linker="aarch64-linux-gnu-g++-13"
target_triple="aarch64-linux-gnu" LD=$linker $compiler c -norun -nolink -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi


objs=""
#compile .ll to .o
for file in $out_dir/*.o; do
  objs="$objs $file"
done

#link .o files
cmd="$linker -lstdc++ -o $name $objs $toolchain_target/lib/libbridge.a $toolchain_target/lib/libLLVM.so.19.1"
echo "$cmd"
$cmd

#rm -rf $dir

if [ "$?" -eq "0" ]; then
  echo "Build successful ${name}"
  rm -r $dir
  exit 0
else
  echo "Build failed"
  exit 1
fi
