#!/bin/bash

dir=$(dirname $0)

echo "building cpp_bridge"

mkdir -p $dir/build

lib=$dir/build/libbridge.a
obj=$dir/build/bridge.o

#compile if only src is modified or lib is deleted
mtnew=$(stat -c %Y $dir/src/bridge.cpp)
if [ -f "$dir/build/.mtime" ]; then
  mtold=$(cat $dir/build/.mtime)
  if [ $mtold = $mtnew ] && [ -f $lib ]; then
    echo "no change" && exit 0
  fi
fi
#mtime is recorded only after a successful build below; a failed compile
#must not poison the stamp (the lib is deleted before recompiling).

#FFI arity gate: .x extern decls vs C++ defs (linker can't catch these)
python3 $dir/../bin/check_ffi.py || exit 1

rm -f $lib $obj

if [ -z "$LLVM_ROOT" ]; then
  llvm_config_bin=$(${dir}/../bin/find_llvm.sh config)
  inc_dir=$($llvm_config_bin --includedir)
else
  inc_dir=$LLVM_ROOT/include
fi

#CXX=$(${dir}/../bin/find_llvm.sh clang)
if [ -z "$CXX" ]; then
  CXX="g++"
fi
if [ -z "$AR" ]; then
  AR="ar"
fi

cmd="$CXX -I$inc_dir -c -o $obj -fPIC -std=c++17 $dir/src/bridge.cpp"

if [ ! -z "$TERMUX_VERSION" ]; then
  #cmd="$cmd -DLLVM20"
  cmd="$cmd -DTERMUX"
fi
echo $cmd
$cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

$AR rcs $lib $obj && ranlib $lib && echo "writing $lib" && echo $mtnew > $dir/build/.mtime

cmd="$CXX -I$inc_dir -o $dir/build/bridge.so -fPIC -std=c++17 $dir/src/bridge.cpp -shared"
echo $cmd && $cmd