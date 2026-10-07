#!/bin/bash

dir=$(dirname $0)

sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

echo "build.sh $1,$2,$3"
if [ ! -d "$1" ]; then
 echo "provide host_tool dir" && exit 1
fi

if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
export version=$2
target_tool=$3
compiler="$host_tool/bin/x"
build=$dir/../build
XCROSS=false
name="stage1"
if [ -d "$target_tool" ]; then
  name="stage1_arm64"
  XCROSS=true
  echo "cross compiling"
fi

out_dir=$build/${name}_out
mkdir -p $out_dir
$dir/cache_env.sh $out_dir

#todo
rm -rf $build
export XTMP=$build/tmp
XCROSS=$XCROSS $dir/apt.sh
XCROSS=$XCROSS $dir/llvm.sh



#NB: gnu-arm64 libLLVM needs libz3 (x86_64/termux do not link it)
if [ "$XCROSS" = true ]; then
  export LIBZ3=$build/tmp/usr/lib/aarch64-linux-gnu/libz3.so.4
fi

export LLVM_ROOT=$build/tmp/usr/lib/llvm-19
export LIBLLVM="$LLVM_ROOT/lib/libLLVM.so.19.1"
#LIBLLVM="$host_tool/lib/libLLVM.so.19.1"
#export LD=$($dir/find_llvm.sh clang)
export LD="g++"
export AR=x86_64-linux-gnu-ar
export CXX=$LD
if [ "$XCROSS" = true ]; then
    export LD=aarch64-linux-gnu-g++
    export AR=aarch64-linux-gnu-ar
    export CXX=$LD
    export target_triple="aarch64-linux-gnu"
    #llvm_lib="$target_tool/lib/libLLVM.so.19.1"
fi
if [ ! -z "$XTERMUX" ]; then
  export LD="./android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
  export target_triple="aarch64-unknown-linux-android24"
fi

# bridge object is arch-specific; force rebuild on arch switches
rm -rf $dir/../cpp_bridge/build
$dir/../cpp_bridge/x.sh || exit 1
bridge_lib=$dir/../cpp_bridge/build/libbridge.a

build(){
  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  $dir/build_ast.sh $compiler $out_dir || exit 1
  LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  $dir/build_resolver.sh $compiler $out_dir || exit 1
  LIB_RESOLVER=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  XLIBNAME=backend XLIBSRC=$dir/../src/backend $dir/build_module.sh $compiler $out_dir || exit 1
  LIB_BACKEND=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  #XLIBNAME=main XLIBSRC=$dir/../src/parser $dir/build_module.sh $compiler $out_dir || exit 1
  #LIB_MAIN=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
  flags="$flags $LIB_AST"
  flags="$flags $LIB_RESOLVER"
  flags="$flags $LIB_BACKEND"
  flags="$flags $LIB_STD"
  flags="$flags $bridge_lib"
  flags="$flags $LIBLLVM"
  if [ ! -z "$LIBZ3" ]; then
    flags="$flags $LIBZ3"
  fi
  #flags="$flags -lxml2"
  #flags="$flags /usr/lib/aarch64-linux-gnu/libxml2.so.16"
  flags="$flags -lstdc++"
  #todo use toolchain's std dir?
  
  cmd="$compiler c -norun -cache $XOPT -stdpath $dir/../src -i $dir/../src -out $out_dir -flags '$flags' -name $name $dir/../src/parser"
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
  if [ "$XCROSS" = true ]; then
    name="stage2_arm64"
    #todo use x86_64 stage1 compiler ,outside of container
    #compiler=$build/stage1_out/stage1
  else
    name="stage2"
    compiler=$final_binary
  fi
  out_dir=$build/${name}_out
  $dir/cache_env.sh $out_dir
  build
  final_binary=${out_dir}/$name
fi

if [ "$XCROSS" = true ]; then
  export ARCH=aarch64
fi

$dir/make_toolchain.sh "$final_binary" $dir/.. ${version} -zip || exit 1
