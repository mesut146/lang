#set -- "./x-toolchain-1.00-x86_64" "./x-toolchain-1.00-aarch64" "1.01"

if [ ! -d "$1" ]; then
 echo "provide host toolchain"
 exit
fi

if [ ! -d "$2" ]; then
 echo "provide target toolchain"
 exit
fi

if [ -z "$3" ]; then
 echo "provide version"
 exit
fi

host_tool=$1
target_tool=$2
version=$3

docker build -t cross -f ./bin/Dockerfile-cross \
--build-arg host_tool=$host_tool \
--build-arg target_tool=$target_tool \
--build-arg version=$version .>d.txt
cat d.txt && rm -f d.txt
docker run -t cross cat /home/lang/log.txt

docker create --name cross cross
docker cp cross:/home/lang/x-toolchain-$version-aarch64.zip .
docker rm -f cross
