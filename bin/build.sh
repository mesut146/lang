dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide host_tool dir" && exit 1
fi

if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
version=$2
target_tool=$3
compiler="$host_tool/bin/x"
build=$dir/../build

name="stage1"
if [ -d "$target_tool" ]; then
  name="stage1_arm64"
fi

out_dir=$build/${name}_out

mkdir -p $out_dir

bridge_lib="$host_tool/lib/libbridge.a"
llvm_lib="$host_tool/lib/libLLVM.so.19.1"
linker=$($dir/find_llvm.sh clang)
if [ -d "$target_tool" ]; then
    linker="aarch64-linux-gnu-g++"
    export target_triple="aarch64-linux-gnu"
    bridge_lib="$target_tool/lib/libbridge.a"
    llvm_lib="$target_tool/lib/libLLVM.so.19.1"
fi
if [ ! -z "$XTERMUX" ]; then
  linker="./android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
  export target_triple="aarch64-unknown-linux-android24"
fi
export LD=$linker

build(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  $dir/build_ast.sh $compiler $out_dir || exit 1
  LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  #flags="$bridge_lib"
  flags="$flags $LIB_AST"
  flags="$flags $LIB_STD"
  flags="$flags $llvm_lib"
  flags="$flags -lstdc++"
  #todo use toolchain's std dir?
  
  cmd="$compiler c -norun -cache -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name $dir/../src/parser"
  if [ ! -z "$XOPT" ]; then
    cmd="$cmd $XOPT"
  fi
  if [ ! -z "$XDEBUG" ]; then
    cmd="$cmd -g"
  fi
  eval $cmd
  if [ ! "$?" -eq "0" ]; then
    echo "error while compiling\n$cmd" && exit 1
  fi
}

build
final_binary=${out_dir}/${name}

cp ${out_dir}/${name} $build

if [ ! -z "$XSTAGE" ]; then
  if [ -d "$target_tool" ]; then
    name="stage2_arm64"
    #todo use x86 stage2 compiler 
  else
    name="stage2"
  fi
  out_dir=$build/${name}_out
  compiler=$final_binary
  build
  final_binary=${out_dir}/$name
fi

old_tool=$host_tool
if [ -d "$target_tool" ]; then
  export ARCH=aarch64
  old_tool=$target_tool
fi

$dir/make_toolchain.sh "$final_binary" $old_tool $dir/.. ${version} -zip || exit 1
