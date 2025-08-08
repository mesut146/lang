dir=$(dirname $0)

if [ -z "$1" ]; then
  echo "enter old import name" && exit 1
fi

if [ -z "$1" ]; then
  echo "enter new import name" && exit 1
fi

old=$1
new=$2


grep -rl $old $dir/../src
grep -rl $old $dir/../src | xargs sed -i "s,${old},${new},g"
