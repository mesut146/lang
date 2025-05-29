set -- "1.01"

if [ -z "$1" ]; then
 echo "provide version"
 exit
fi
version=$1

docker build -t cross -f ./bin/Dockerfile-cross .
docker create --name cross cross
docker cp cross:/home/lang/x-toolchain-$version-aarch64.zip .
docker rm -f cross
