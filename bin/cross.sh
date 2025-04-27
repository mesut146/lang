dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

toolchain=$1
compiler="$toolchain/bin/x"
build=$dir/../build
name="x_arm64"
out_dir=$build/${name}_out

target_triple="aarch64-linux-gnu" $compiler c -cache -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi
#todo use toolchain's std dir?
linker=$($dir/find_llvm.sh clang)
target_triple="aarch64-linux-gnu" LD=$linker $compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

suffix=$(./find_llvm.sh)

objs=""
#compile .ll to .o
for file in $out_dir/*.ll; do
  echo "compiling $file"
  if [ "$2" == "-pic" ]; then
    llc$suffix -filetype=obj --relocation-model=pic $file
  else
    llc$suffix -filetype=obj $file
  fi

  if [ ! "$?" -eq "0" ]; then
    echo "Compilation failed for $file"
    exit 1
  fi
  nm="${file%.*}"
  objs="$objs ${nm}.o"
done

#link .o files
cmd="clang++$suffix -lstdc++ -o $name $objs ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so"
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
