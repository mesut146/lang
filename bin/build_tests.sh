dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler binary"
 exit 1
fi

compiler=$1
build=$dir/../build

name="xtest"
out_dir=$build/${name}_out
mkdir -p $out_dir

export LD=$($dir/find_llvm.sh clang)

$dir/build_std.sh $compiler $out_dir || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
$dir/build_ast.sh $compiler $out_dir || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
$dir/build_resolver.sh $compiler $out_dir || exit 1
LIB_RESOLVER=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt
  
flags="$LIB_AST $LIB_STD $LIB_RESOLVER"

sudo ()
{
    [[ $EUID = 0 ]] || set -- command sudo "$@"
    "$@"
}
if [ ! -z "$XPERF" ]; then
  sudo apt-get install -y google-perftools graphviz
  go install github.com/google/pprof@latest
  flags="$flags /usr/lib/x86_64-linux-gnu/libprofiler.so.0"
fi

$compiler c -norun -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name -flags "$flags" $dir/../src/tests
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  exit 1
fi

bin=$out_dir/$name
if [ ! -z "$XPERF" ]; then
  #export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libprofiler.so.0"
  CPUPROFILE=./prof.out $bin $2 $3 $4
  go run github.com/google/pprof@latest -top "$bin" ./prof.out
else
  $bin $2 $3 $4
fi