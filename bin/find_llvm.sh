suffix=""

if command -v llvm-config-19 2>&1 >/dev/null; then
  suffix=-19
else
  if command -v llvm-config 2>&1 >/dev/null; then
    suffix=""
  else
    echo "cant find llvm-config"
    exit
  fi
fi

echo "$suffix"

