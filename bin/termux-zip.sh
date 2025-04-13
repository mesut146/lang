dir=$1
suffix=$2

rm -f x-ll$suffix.zip

if [[ "$dir" == */ ]]; then
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

if [ -n "$2" ]; then
 suffix="-$2"
fi

for f in $dir/*.ll; do
  echo $f
  zip x-ll$suffix.zip $f
done
