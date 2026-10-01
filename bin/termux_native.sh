#!/bin/bash
# Native Termux bootstrap: rebuild the compiler ON the device using a
# previous Termux toolchain (needs >= 1.04, which ships libbridge.a).
#
# No NDK, Docker, Debian downloads or LLVM packages are needed: codegen
# runs through the toolchain's own libLLVM.so.19 + libbridge.a, and the
# system clang++ only links final binaries.
#
# On device, first time:
#   pkg install clang lld binutils make zip unzip patchelf
#   # get a bootstrap toolchain (any recent release asset):
#   unzip x-toolchain-<ver>-termux-aarch64.zip
# Then:
#   ./bin/termux_native.sh x-toolchain-<ver>-termux-aarch64 <new-ver>
# Optional: XJOBS=$(nproc) for parallel lib builds (warm device!).

dir=$(dirname $0)

echo "termux_native.sh $1,$2"
if [ ! -d "$1" ]; then
 echo "provide host_tool dir (previous termux toolchain)" && exit 1
fi

if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
version=$2
compiler="$host_tool/bin/x"
build=$dir/../build
name="stage1_termux"

if [ ! -f "$compiler" ]; then
  echo "host compiler not found: $compiler" && exit 1
fi
if [ ! -f "$host_tool/lib/libLLVM.so.19" ] && [ ! -f "$host_tool/lib/libLLVM.so" ]; then
  echo "no Termux libLLVM in $host_tool/lib" && exit 1
fi
if [ ! -f "$host_tool/lib/libbridge.a" ]; then
  echo "no libbridge.a in $host_tool/lib (need toolchain >= 1.04)" && exit 1
fi

# wipe build AFTER resolving vars, BEFORE creating out_dir
rm -rf $build
export XTMP=$build/tmp
out_dir=$build/${name}_out
mkdir -p $out_dir

export XTERMUX=1
#no apt/NDK/llvm downloads here: reuse the toolchain's own libs
if [ -f "$host_tool/lib/libLLVM.so.19" ]; then
  export LIBLLVM="$host_tool/lib/libLLVM.so.19"
else
  export LIBLLVM="$host_tool/lib/libLLVM.so"
fi
bridge_lib="$host_tool/lib/libbridge.a"

#make_toolchain ships $BRIDGE_LIB; on device there is no cpp_bridge/build
#(gitignored), so pass the host toolchain's bridge through for the next
#native generation.
export BRIDGE_LIB="$bridge_lib"

#Termux system linker; default target is already aarch64-linux-android
export LD="clang++"
unset target_triple
export AR="ar"
export CXX=$LD
#clang++ links libc++ by itself; -lstdc++ does not exist on Termux
if [ -z "${STDCPP:-}" ]; then
  export STDCPP=""
fi

  $dir/build_std.sh $compiler $out_dir || exit 1
  LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  $dir/build_ast.sh $compiler $out_dir || exit 1
  LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  $dir/build_resolver.sh $compiler $out_dir || exit 1
  LIB_RESOLVER=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  XLIBNAME=backend XLIBSRC=$dir/../src/backend $dir/build_module.sh $compiler $out_dir || exit 1
  LIB_BACKEND=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

  flags="$flags $LIB_AST"
  flags="$flags $LIB_RESOLVER"
  flags="$flags $LIB_BACKEND"
  flags="$flags $LIB_STD"
  flags="$flags $bridge_lib"
  flags="$flags $LIBLLVM"
  flags="$flags $STDCPP"
  dirr=$(realpath $dir)
  cmd="$compiler c -norun -cache -stdpath $dirr/../src -i $dirr/../src -out $out_dir -flags '$flags' -name $name $dirr/../src/parser"
  if [ ! -z "$XDEBUG" ]; then
    cmd="$cmd -g"
  fi
  eval $cmd
  if [ ! "$?" -eq "0" ]; then
    echo "error while compiling\n$cmd" && exit 1
  fi

final_binary=${out_dir}/${name}

cp ${out_dir}/${name} $build

XTERMUX=1 ARCH=termux-aarch64 $dir/make_toolchain.sh "$final_binary" $dir/.. ${version} -zip || exit 1
