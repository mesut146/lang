dir=$(dirname $0)
#run from github workflow

echo "docker.sh $1,$2,$3"

if [ ! -d "$1" ]; then
 echo "provide host toolchain" && exit 1
fi
if [ -z "$2" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
version=$2

#move tools inside project dir otherwise docker cant access them
root=$(realpath $dir/..)
host_real=$(realpath $host_tool)
if [[ ! "$host_real" = $root/* ]]; then
    cp -r $host_tool $root
    host_tool=$root/$(basename $host_tool)
fi
name="test"
docker builder prune -f
docker rmi -f $name
docker build \
-t $name \
-f ./bin/Dockerfile_x64 \
--build-arg host_tool=$host_tool \
--build-arg XTMP=$XTMP \
  .

docker rm -f x64c
docker run $name sh -c "cat ./src/std/string.x"
#docker run --rm --name x64c $name sh -c "XOPT='$XOPT' XSTAGE='$XSTAGE' $dir/stage1.sh $host_tool $version"

#docker create --name crossc cross
#docker cp crossc:/home/lang/x-toolchain-$version-aarch64.zip .
