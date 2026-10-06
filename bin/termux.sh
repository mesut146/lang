#!/bin/bash

dir=$(dirname $0)

sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}

echo "stage1.sh $1,$2,$3"
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
name="stage1_termux"
XCROSS=true

if [ ! -f "$compiler" ]; then
  echo "host compiler not found: $compiler" && exit 1
fi
if [ ! -d "$target_tool" ]; then
  echo "provide target_tool dir with Termux libLLVM (e.g. x-toolchain-1.00-termux-aarch64)" && exit 1
fi

# wipe build AFTER resolving vars, BEFORE creating out_dir
rm -rf $build
export XTMP=$build/tmp
out_dir=$build/${name}_out
mkdir -p $out_dir

export XTERMUX=1
XCROSS=$XCROSS $dir/apt_cross.sh
XTERMUX=1 XCROSS=$XCROSS $dir/llvm.sh
# NB: Debian arm64 libLLVM from llvm.sh is NOT usable for Android linking.
# libLLVM must come from the previous Termux toolchain (built against NDK/Termux llvm).


export LLVM_ROOT=$build/tmp/usr/lib/llvm-19
#libLLVM must be the Android/Termux one, not the Debian x86_64 one
if ls "$target_tool"/lib/libLLVM.so* >/dev/null 2>&1; then
  export LIBLLVM=$(ls "$target_tool"/lib/libLLVM.so* | head -n 1)
else
  echo "no libLLVM.so* in $target_tool/lib" && exit 1
fi
#LIBLLVM="$host_tool/lib/libLLVM.so.19.1"

NDK_ROOT="$dir/../android-ndk-r27c"
if [ ! -x "$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++" ]; then
  echo "NDK not found at $NDK_ROOT (apt_cross.sh should have downloaded it)" && exit 1
fi
export LD="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++"
export target_triple="aarch64-linux-android24"
  
export AR="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
export CXX=$LD
#llvm_lib="$target_tool/lib/libLLVM.so.19.1"

export TERMUX_VERSION="0.118.1"
# bridge object is arch-specific; force rebuild on arch switches
rm -rf $dir/../cpp_bridge/build
$dir/../cpp_bridge/x.sh || exit 1
bridge_lib=$dir/../cpp_bridge/build/libbridge.a


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
  #flags="$flags -lxml2"
  #flags="$flags /usr/lib/aarch64-linux-gnu/libxml2.so.16"
  flags="$flags -lstdc++"
  #todo use toolchain's std dir?
  dirr=$(realpath $dir)
  cmd="$compiler c -norun -cache $XOPT -stdpath $dirr/../src -i $dirr/../src -out $out_dir -flags '$flags' -name $name $dirr/../src/parser"
  if [ ! -z "$XDEBUG" ]; then
    cmd="$cmd -g"
  fi
  eval $cmd
  if [ ! "$?" -eq "0" ]; then
    echo "error while compiling\n$cmd" && exit 1
  fi

final_binary=${out_dir}/${name}

cp ${out_dir}/${name} $build

if [ "$XCROSS" = true ]; then
  export ARCH=termux-aarch64
fi

XTERMUX=1 ARCH=termux-aarch64 $dir/make_toolchain.sh "$final_binary" $dir/.. ${version} -zip || exit 1