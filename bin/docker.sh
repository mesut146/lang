dir=$(dirname $0)
#run from github workflow

echo "docker.sh $1,$2,$3"

if [ ! -d "$1" ]; then
 echo "provide host toolchain" && exit 1
fi
if [ ! -d "$2" ]; then
 echo "provide target toolchain" && exit 1
fi
if [ -z "$3" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
target_tool=$2
version=$3
termux=$4

docker builder prune -f
#--no-cache
NOCACHE=true
#move tools inside project dir otherwise docker cant access them
root=$(realpath $dir/..)
host_real=$(realpath $host_tool)
if [[ ! "$host_real" = $root/* ]]; then
    cp -r $host_tool $root && host_tool=$root/$(basename $host_tool)
    cp -r $target_tool $root && target_tool=$root/$(basename $target_tool)
fi
if [[ $NOCACHE = true || $(docker images cross:latest) != *"cross"* ]]; then
docker build --progress=plain -t cross -f ./bin/Dockerfile \
--build-arg host_tool=$host_tool \
--build-arg target_tool=$target_tool \
--build-arg termux=$termux \
--build-arg XTMP=$XTMP \
--no-cache --pull .
fi

docker run --name crossc cross sh -c "XOPT='$XOPT' XSTAGE='$XSTAGE' $dir/build.sh $host_tool $version $target_tool"

#docker create --name crossc cross
docker cp crossc:/home/lang/x-toolchain-$version-aarch64.zip .
docker rm -f crossc
