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

name="$XLIBNAME"
out_dir=$build/${name}_out


mkdir -p $out_dir
$dir/cache_env.sh $out_dir

# Parallel per-file compilation by default (bin/jobs.sh: CPU count capped at
# 8); XJOBS overrides it, XJOBS=1 forces the serial path.
JOBS="-j $($dir/jobs.sh)"

#Optimization level. The release build (bin/build.sh, stage1/stage2.sh) passes
#XOPT=-O2, but it used to reach only the final src/parser compile, so a released
#compiler ran its whole front end (std/ast/resolver/backend) unoptimized while
#users spend most of a compile there. Front-end libraries now take the level.
#`backend` is pinned to -O0: an -O2 backend crashes nondeterministically in
#compile_dir (corrupted sret pointer; see doc/todo, "backend at -O2"). Do not
#unpin it before that is root-caused.
#The cache keys on XOPT via cache_env.sh, so switching levels cannot reuse
#foreign objects.
opt="$XOPT"
if [ "$name" = "backend" ]; then
  opt=""
fi
cmd="$compiler c -static -cache $JOBS $opt -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $XLIBSRC"
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  echo "$cmd"
  exit 1
fi

LIB_OUT="${out_dir}/${name}.a"
echo "$LIB_OUT">$dir/tmp.txt
