#!/bin/bash
clear

dir=$(dirname $0)

cd $dir/..
zip="tmp.zip"
rm ./cpp_bridge/build -rf
zip -q -r $zip ./bin ./src ./tests ./cpp_bridge/src ./cpp_bridge/x.sh ./cpp_bridge/CMakeLists.txt ./doc ./grammar

gcloud cloud-shell scp localhost:$zip cloudshell:/home/mesutdogansoy/lang

host_tool="x-toolchain-1.00-x86_64"

if [ -z "$XVER" ]; then
    XVER="v2"
fi
cmd="cd lang/ && unzip -u -o tmp.zip && rm -f tmp.zip"
if [ "$1" = "-termux" ]; then
  cmd="$cmd&&./bin/docker.sh $host_tool x-toolchain-1.00-termux-aarch64 v-tmux-termux -termux"
elif [ "$1" = "-cross" ]; then
  cmd="$cmd&&"
  if [ ! -z "$XSTAGE" ]; then
    cmd="$cmd XSTAGE=1"
  fi
  cmd="$cmd ./bin/docker.sh $host_tool x-toolchain-1.00-aarch64 $XVER"
elif [ "$1" = "-bt" ]; then
  name="x2"
  cmd="$cmd&&./bin/bt.sh $host_tool/bin/x $name&&./bin/test.sh ./build/$name"
elif [ "$1" = "-build" ]; then
  cmd="$cmd&&"
  if [ ! -z "$XSTAGE" ]; then
    cmd="$cmd XSTAGE=1"
  fi
  cmd="$cmd ./bin/build.sh $host_tool $XVER"
elif [ "$1" = "-stage1" ]; then
  cmd="$cmd&&./bin/stage1.sh $host_tool $XVER"
elif [ "$1" = "-stage2" ]; then
  stage1="./build/stage1_out/stage1"
  cmd="$cmd&&./bin/stage2.sh $stage1 $XVER"
elif [ "$1" = "-stage11" ]; then
cmd="$cmd&&./bin/docker_x64.sh $host_tool v2"
elif [ "$1" = "-test" ]; then
  cmd="$cmd&&./bin/build.sh $host_tool v2 &&./bin/test.sh ./build/stage1 $2 $3"
fi
gcloud cloud-shell ssh --command="$cmd"


rm -f $zip
