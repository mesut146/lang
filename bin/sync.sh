dir=$(dirname $0)

cd $dir/..
zip="tmp.zip"
zip -q -r $zip ./bin ./src ./tests ./cpp_bridge ./doc ./grammar

gcloud cloud-shell scp localhost:$zip cloudshell:/home/mesutdogansoy/lang


cmd="cd lang/ && unzip -u -o tmp.zip && rm -f tmp.zip"
if [ $1 = "-termux" ]; then
  cmd="$cmd&&./bin/docker.sh x-toolchain-1.00-x86_64 x-toolchain-1.00-termux-aarch64 v-tmux-termux -termux"
else
  name="x2"
  cmd="$cmd&&./bin/bt.sh x-toolchain-1.00-x86_64/bin/x $name&&./bin/test.sh ./build/$name"
fi
gcloud cloud-shell ssh --command="$cmd"


rm -f $zip
