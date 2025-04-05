#suffix="-19"
suffix=""
libdir=$(llvm-config$suffix --libdir)

unzip -o x-ll.zip

dir=x-termux_out
objs=""
for file in $dir/*.ll; do
  echo "compiling $file"
  llc$suffix -filetype=obj --relocation-model=pic $file
  name="${file%.*}"
  objs="$objs $name.o"
done
echo $objs
#clang++ -lstdc++ -o x-termux x-termux.a std-termux.a ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so

clang++$suffix -lstdc++ -o x-termux $objs ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so
