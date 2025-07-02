dir=$(dirname $0)

echo "building cpp_bridge"

mkdir -p $dir/build

lib=$dir/build/libbridge.a
obj=$dir/build/bridge.o
shared=$dir/build/libbridge.so


rm -f $lib $obj $shared


llvm_config_bin=$(${dir}/../bin/find_llvm.sh config)
clang_bin=$(${dir}/../bin/find_llvm.sh clang)
llvm_dir=$($llvm_config_bin --includedir)

if [ ! -z "$CC" ]; then
  clang_bin="$CC"
fi

echo "llvm_dir=$llvm_dir"

if [ ! -z "$TERMUX_VERSION" ]; then
  $clang_bin -I$llvm_dir -c -o $obj -fPIC $dir/src/bridge.cpp -DLLVM20
else
  $clang_bin -I$llvm_dir -c -o $obj -fPIC $dir/src/bridge.cpp
fi
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

ar rcs $lib $obj && ranlib $lib && echo "writing $lib"
$clang_bin -I$llvm_dir -shared -o $shared $obj && echo "writing $shared"
