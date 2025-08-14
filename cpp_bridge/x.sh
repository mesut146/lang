dir=$(dirname $0)

echo "building cpp_bridge"

mkdir -p $dir/build

lib=$dir/build/libbridge.a
obj=$dir/build/bridge.o
shared=$dir/build/libbridge.so


rm -f $lib $obj $shared

if ! command -v llvm-config-19 2>&1 >/dev/null; then
  wget https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 19
  rm ./llvm.sh
fi

llvm_config_bin=$(${dir}/../bin/find_llvm.sh config)
#clang_bin=$(${dir}/../bin/find_llvm.sh clang)
clang_bin="g++"
llvm_dir=$($llvm_config_bin --includedir)

if [ ! -z "$CC" ]; then
  clang_bin="$CC"
fi

echo "llvm_dir=$llvm_dir"

cmd="$clang_bin -I$llvm_dir -c -o $obj -fPIC -std=c++17 $dir/src/bridge.cpp"

if [ ! -z "$TERMUX_VERSION" ]; then
  cmd="$cmd -DLLVM20"
fi
echo $cmd
$cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

ar rcs $lib $obj && ranlib $lib && echo "writing $lib"
$clang_bin -I$llvm_dir -shared -o $shared $obj && echo "writing $shared"
