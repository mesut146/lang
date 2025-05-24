dir=$(dirname $0)

if [ ! -d "$1" ]; then
 echo "provide toolchain dir"
 exit
fi

toolchain=$1

$toolchain/bin/x c . -out $dir/../build/lsp -stdpath $toolchain/src -std