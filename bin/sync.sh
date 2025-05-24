dir=$(dirname $0)

cd $dir/..
zip="tmp.zip"
zip -q -r $zip ./bin ./src ./tests ./cpp_bridge ./doc ./grammar

gcloud cloud-shell scp localhost:$zip cloudshell:/home/mesutdogansoy/lang
gcloud cloud-shell ssh --command="cd lang/ && unzip -u -o tmp.zip && rm -f tmp.zip"

rm -f $zip
