dir=$(dirname $0)

cd $dir/..
zip="tmp.zip"
zip -q -r $zip ./bin ./src ./tests ./cpp_bridge ./doc ./grammar

gcloud cloud-shell scp localhost:$zip cloudshell:/home/mesutdogansoy/lang


cmd="cd lang/ && unzip -u -o tmp.zip && rm -f tmp.zip"
name="x2"
cmd="$cmd&&./bin/bt.sh x-toolchain-1.00-x86_64/bin/x $name&&./bin/test.sh ./build/$name"
gcloud cloud-shell ssh --command="$cmd"


rm -f $zip
