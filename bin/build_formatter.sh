dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler binary"
 exit 1
fi

compiler=$1
build=$dir/../build
name="fmt"
out_dir=$build/${name}_out

mkdir -p $build

$dir/build_std.sh $compiler || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

$dir/build_ast.sh $compiler || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

flags="$LIB_AST $LIB_STD"

$compiler c -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name -flags "$flags" $dir/../src/formatter
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  exit 1
fi
