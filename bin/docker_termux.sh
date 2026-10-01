dir=$(dirname $0)
#run from github workflow

echo "docker_termux.sh $1,$2,$3"

host_tool=$1
version=$2
target_tool=$3
if [ -z "$target_tool" ]; then
  target_tool="x-toolchain-1.00-termux-aarch64"
fi
if [ ! -d "$target_tool" ]; then
  gh release download --skip-existing v1.00 -p "x-toolchain-1.00-termux-aarch64.zip" && unzip -n x-toolchain-1.00-termux-aarch64.zip || true
fi

if [ ! -d "$1" ]; then
 echo "provide host toolchain" && exit 1
fi
if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi
#if [ ! -d "$3" ]; then
# echo "provide target toolchain" && exit 1
#fi

host_tool=$1
version=$2
target_tool=$3
if [ -z "$target_tool" ]; then
  target_tool="x-toolchain-1.00-termux-aarch64"
fi

docker builder prune -f
docker rmi -f cross
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
--build-arg termux=1 \
--build-arg XTMP=$XTMP \
--no-cache --pull .
fi

docker run --name crossc cross sh -c "XOPT='$XOPT' XSTAGE='$XSTAGE' $dir/termux.sh $host_tool $version $target_tool" || exit 1
docker cp crossc:/home/lang/x-toolchain-$version-termux-aarch64.zip . || exit 1
docker rm -f crossc
