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
$dir/cache_env.sh $out_dir

# Parallel per-file compilation by default (bin/jobs.sh: CPU count capped at
# 8); XJOBS overrides it, XJOBS=1 forces the serial path.
JOBS="-j $($dir/jobs.sh)"

#Optimization level: the front-end libraries take the caller's $XOPT like
#bin/build_module.sh does (the release build sets XOPT=-O2). Without this the
#shipped std/ast/resolver ran the default pipeline while the backend was -O2.
opt="$XOPT"
cmd="$compiler c -static -cache $JOBS $opt -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $dir/../src/std"
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling std"
  echo $cmd
  exit 1
fi

LIB_STD="${out_dir}/${name}.a"
echo "$LIB_STD">$dir/tmp.txt