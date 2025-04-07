#suffix="-19"
suffix=""
libdir=$(llvm-config$suffix --libdir)
dir=x-termux_out
objs=""

rm -rf $dir
unzip -q -o x-ll.zip && echo "unzip done"


#compile .ll to .o
for file in $dir/*.ll; do
  echo "compiling $file"
  if [ "$1" == "-pic" ]; then
    llc$suffix -filetype=obj --relocation-model=pic $file
  else
    llc$suffix -filetype=obj $file
  fi

  if [ ! "$?" -eq "0" ]; then
    echo "Compilation failed for $file"
    exit 1
  fi
  name="${file%.*}"
  objs="$objs $name.o"
done

#link .o files
cmd="clang++$suffix -lstdc++ -o x-termux $objs ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so"
echo "$cmd"
$cmd

if [ "$?" -eq "0" ]; then
  echo "Build successful"
  rm -r $dir
  exit 0
else
  echo "Build failed"
  exit 1
fi
