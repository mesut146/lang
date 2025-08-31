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

docker builder prune -f
#--no-cache
NOCACHE=true
#move tools inside project dir otherwise docker cant access them
root=$(realpath $dir/..)
host_real=$(realpath $host_tool)
if [[ ! "$host_real" = $root/* ]]; then
    cp -r $host_tool $root && host_tool=$root/$(basename $host_tool)
fi
if [[ $NOCACHE = true || $(docker images x64:latest) != *"x64"* ]]; then
docker build --progress=plain -t x64 -f ./bin/Dockerfile_x64 \
--build-arg host_tool=$host_tool \
--build-arg XTMP=$XTMP \
--no-cache --pull .
fi

docker rm -f x64c
docker run --name x64c x64 sh -c "XOPT='$XOPT' XSTAGE='$XSTAGE' $dir/stage1.sh $host_tool $version"

#docker create --name crossc cross
#docker cp crossc:/home/lang/x-toolchain-$version-aarch64.zip .
