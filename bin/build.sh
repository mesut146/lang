dir=$(dirname $0)

if [ -z "$1" ]; then
 echo "provide compiler"
 exit
fi

compiler="$1"
name="x2"
build=$dir/../build
mkdir -p $build
out_dir=$build/${name}_out

echo "compiler=$1"
echo "out=$out_dir"

bridge_lib=$dir/../cpp_bridge/build/libbridge.a

llvm_config_bin=$(${dir}/find_llvm.sh config)
libdir=$(${llvm_config_bin} --libdir)
libs="$libdir/libLLVM.so"
flags="$bridge_lib"
flags="$flags $out_dir/std.a"
flags="$flags $libs"
flags="$flags -lstdc++"

$dir/../cpp_bridge/x.sh

#compile std
$compiler c -static -stdpath $dir/../src -i $dir/../src -out $out_dir $dir/../src/std

#vendor=x4 compiler_name=$name version=1.7 \
$compiler c -norun -cache -stdpath $dir/../src -i $dir../src -out $out_dir -flags "$flags" -name $name $dir/../src/parser

cp ${out_dir}/${name} $build
