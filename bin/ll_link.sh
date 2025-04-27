suffix=$(./find_llvm.sh)
llvm_config="llvm-config${suffix}"
libdir=$($llvm_config --libdir)
name="x-$(uname -m)"
dir=${name}_out
objs=""

rm -rf $dir
unzip -q -o -d $dir x-ll.zip && echo "unzip done"


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
  nm="${file%.*}"
  objs="$objs ${nm}.o"
done

#link .o files
cmd="clang++$suffix -lstdc++ -o $name $objs ../cpp_bridge/build/libbridge.a $libdir/libLLVM.so"
echo "$cmd"
$cmd

#rm -rf $dir

if [ "$?" -eq "0" ]; then
  echo "Build successful ${name}"
  rm -r $dir
  exit 0
else
  echo "Build failed"
  exit 1
fi
