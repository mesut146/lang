dir=$1
suffix=$2
cur=$(dirname $0)
rm -f x-ll$suffix.zip

if [[ "$dir" == */ ]]; then
 #trim trailing '/'
 dir="${dir::-1}"
fi

if [ -n "$dir" ]; then
 if [ ! -d "$dir" ]; then
  echo "dir doesnt exist '$1'"
  exit 1
 fi
else
 echo "please specify dir"
 exit 1
fi

dir=$(realpath $dir)

if [ -n "$2" ]; then
 suffix="-$2"
fi

build=$(dirname $dir)
echo "build=$build"

zipfile="$(pwd)/x-ll$suffix.zip"
echo "zip $zipfile"

#cd $build/x3-arm_out
cd $dir

for f in *.ll; do
  e=$(basename $(dirname $f))/$(basename $f)
  echo "ll=$f"
  zip -q $zipfile $f
done
