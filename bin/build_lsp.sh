dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler binary"
 exit 1
fi

compiler=$1
build=$dir/../build
name="lsp"
out_dir=$build/${name}_out

mkdir -p $build

$dir/build_std.sh $compiler $out_dir || exit 1
LIB_STD=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

$dir/build_ast.sh $compiler $out_dir || exit 1
LIB_AST=$(cat "$dir/tmp.txt") && rm -rf $dir/tmp.txt

flags="$LIB_AST $LIB_STD"

$compiler c -norun -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name -flags "$flags" $dir/../src/lsp
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  exit 1
fi
