dir=$(dirname $0)

cd $dir/..
zip="tmp.zip"
zip -q -r $zip ./bin ./src ./tests ./cpp_bridge ./doc ./grammar

gcloud cloud-shell scp localhost:$zip cloudshell:/home/mesutdogansoy/lang

host_tool="x-toolchain-1.00-x86_64"

cmd="cd lang/ && unzip -u -o tmp.zip && rm -f tmp.zip"
if [ "$1" = "-termux" ]; then
  cmd="$cmd&&./bin/docker.sh $host_tool x-toolchain-1.00-termux-aarch64 v-tmux-termux -termux"
elif [ "$1" = "-cross" ]; then
  cmd="$cmd&&./bin/docker.sh $host_tool x-toolchain-1.00-aarch64 v2"
else
  name="x2"
  cmd="$cmd&&./bin/bt.sh $host_tool/bin/x $name&&./bin/test.sh ./build/$name"
fi
gcloud cloud-shell ssh --command="$cmd"


rm -f $zip
