#suffix="-19"
suffix=""
libdir=$(llvm-config$suffix --libdir)

unzip -o x-ll.zip

dir=x-termux_out
objs=""
for file in $dir/*.ll; do
  echo "compiling $file"
  llc$suffix -filetype=obj --relocation-model=pic $file
  if [ ! "$?" -eq "0" ]; then
    echo "Compilation failed for $file"
    exit 1
  fi
  name="${file%.*}"
  objs="$objs $name.o"
done
echo $objs
#clang++ -lstdc++ -o x-termux x-termux.a std-termux.a ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so

clang++$suffix -lstdc++ -o x-termux $objs ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so

if [ "$?" -eq "0" ]; then
  echo "Build successful"
  rm -r $dir
  exit 0
else
  echo "Build failed"
  exit 1
fi