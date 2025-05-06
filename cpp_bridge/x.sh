clear
dir=$(dirname $0)

mkdir -p $dir/build

lib=$dir/build/libbridge.a
obj=$dir/build/bridge.o
shared=$dir/build/libbridge.so


rm -f $lib $obj $shared

llvm_suffix="-19"
llvm_config_bin=llvm-config$llvm_suffix
llvm_dir="/usr/lib/llvm$llvm_suffix/include"
clang_bin=""

if command -v $llvm_config_bin 2>&1 >/dev/null
then
    llvm_dir=$($llvm_config_bin --includedir)
fi

echo "llvm_dir=$llvm_dir"



find_clang(){
  if command -v clang++-19 2>&1 >/dev/null; then
    clang_bin="clang++-19"
  elif command -v clang++ 2>&1 >/dev/null; then
    clang_bin="clang++"
  else
    echo "can't find clang++"
    exit 1
  fi
  echo "clang_bin=$clang_bin"
}

find_clang


$clang_bin -I$llvm_dir -c -o $obj $dir/src/bridge.cpp
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling"
  exit 1
fi

ar rcs $lib $obj && /usr/bin/ranlib $lib && echo "writing $lib"

#$clang_bin -I$llvm_dir -shared -o $shared $dir/src/bridge.cpp && echo "writing $shared"
$clang_bin -I$llvm_dir -shared -o $shared $obj && echo "writing $shared"
