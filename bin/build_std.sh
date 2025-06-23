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

name="std"
out_dir=$build/${name}_out

mkdir -p $out_dir

cmd="$compiler c -static -cache -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $dir/../src/std"
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling std"
  echo $cmd
  exit 1
fi

LIB_STD="${out_dir}/${name}.a"
echo "$LIB_STD">$dir/tmp.txt