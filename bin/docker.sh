set -- "1.01"

if [ -z "$1" ]; then
 echo "provide version"
 exit
fi
docker build -t cross -f ./bin/Dockerfile-cross .
docker cp cross:/home/lang/x-toolchain-$version-aarch64.zip .
