set -- "./x-toolchain-1.00-x86_64" "./x-toolchain-1.00-aarch64" "1.01"

if [ -z "$1" ]; then
 echo "provide host toolchain dir"
 exit
fi

if [ ! -d "$2" ]; then
 echo "provide target toolchain dir"
 exit
fi

if [ -z "$3" ]; then
 echo "provide version"
 exit
fi

tool_host=$1
tool_target=$2
version=$3

./bin/cross.sh $tool_host $tool_target $version
