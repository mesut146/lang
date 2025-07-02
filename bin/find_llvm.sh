find_clang(){
  if command -v clang++-19 2>&1 >/dev/null; then
    echo "clang++-19"
  elif command -v clang++ 2>&1 >/dev/null; then
    echo "clang++"
  elif command -v g++ 2>&1 >/dev/null; then
    echo "g++"
  else
    echo "can't find clang++"
    exit 1
  fi
}

find_config(){
  if command -v llvm-config-19 2>&1 >/dev/null; then
    echo "llvm-config-19"
  elif command -v llvm-config 2>&1 >/dev/null; then
    echo "llvm-config"
  else
    echo "cant find llvm-config"
    exit 1
  fi
}

find_suffix(){
  if command -v llvm-config-19 2>&1 >/dev/null; then
    echo "-19"
  elif command -v llvm-config 2>&1 >/dev/null; then
    echo ""
  else
    echo "cant find llvm-config"
    exit 1
  fi
}

if [ "$1" = "config" ]; then
  find_config
elif [ "$1" = "suffix" ]; then
  find_suffix
elif [ "$1" = "clang" ]; then
  find_clang
else
  echo "invalid call to $0, arg=$1"
  exit 1
fi

