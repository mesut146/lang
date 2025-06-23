dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler binary"
 exit 1
fi

compiler=$1
build=$dir/../build

if [ ! -z "$2" ]; then
  build=$2
fi

name="ast"
out_dir=$build/${name}_out


mkdir -p $out_dir

$compiler c -static -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $dir/../src/ast
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  exit 1
fi

LIB_AST="${out_dir}/${name}.a"
echo "$LIB_AST">$dir/tmp.txt
