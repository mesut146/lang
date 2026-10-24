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
#users spend most of a compile there. Front-end libraries take the level.
#`backend` used to be pinned to -O0: the crash that put it there was a resolver
#bug (a plain `Node` from ast shadowed llist's `Node<T>`, so the struct was 12
#bytes in modules that resolved ast's `Node` first and 24 in std; -O2 frames then
#overwrote their saved registers). The resolver fix `d640a2b` shipped in v1.19
#and releases bootstrap from the previous release tag, so every supported
#bootstrap (>= v1.19) lays the struct out correctly and the pin is gone:
#building the backend at -O2 makes the shipped compiler's front end ~7% faster
#on a module set (see handoff.md). Bootstrapping from a pre-v1.19 compiler is no
#longer supported: it can still emit the bad layout for an -O2 backend.
#The cache keys on XOPT via cache_env.sh, so switching levels cannot reuse
#foreign objects.
opt="$XOPT"
#-nostd: an archive build links nothing, so the implicit std archive must not
#be built on the side (see handle_c; older bootstrap compilers still do it
#for -static).
cmd="$compiler c -static -nostd -cache $JOBS $opt -out $out_dir -stdpath $dir/../src -i $dir/../src -name $name $XLIBSRC"
eval $cmd
if [ ! "$?" -eq "0" ]; then
  echo "error while compiling $name"
  echo "$cmd"
  exit 1
fi

LIB_OUT="${out_dir}/${name}.a"
echo "$LIB_OUT">$dir/tmp.txt
