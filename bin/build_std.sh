dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler binary"
 exit 1
fi

compiler=$1
build=$dir/../build
name="std"
out_dir=$build/${name}_out

mkdir -p $build

$compiler c -static -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $dir/../src/std
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling std"
  exit 1
fi

LIB_STD="$out_dir/$name.a"
echo "$LIB_STD">$dir/tmp.txt