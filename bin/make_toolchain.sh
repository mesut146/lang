
if [ ! -f "$1" ]; then
  echo "provide compiler binary $1"
  exit
fi

if [ ! -d "$2" ]; then
  echo "provide output dir \$2"
  exit
fi

if [ -z "$3" ]; then
  echo "enter version \$3"
  exit
fi
if [ -z "$LIBLLVM" ]; then
  echo "missing \$LIBLLVM" && exit 1
fi

is_zip=false

if [ "$4" = "-zip" ]; then
  is_zip=true
fi

cur=$(dirname $0)

binary="$1"
out_dir="$2"
version="$3"
arch=$ARCH

if [ -z $ARCH ]; then
  arch=$(uname -m)
fi
# termux toolchain must not collide with gnu aarch64
if [ ! -z "$XTERMUX" ] && [ "$arch" = "aarch64" ]; then
  arch="termux-aarch64"
fi
name="x-toolchain-${version}-${arch}"
dir=$out_dir/$name

mkdir -p $dir
mkdir -p $dir/bin
mkdir -p $dir/lib
mkdir -p $dir/src

cp $binary $dir/bin/x
cp $LIBLLVM $dir/lib
# Android libLLVM SONAME is libLLVM.so while the file is libLLVM.so.19;
# loader looks up SONAME, so provide the symlink next to it.
llvm_base=$(basename $LIBLLVM)
if [ "$llvm_base" != "libLLVM.so" ]; then
  ln -sf "$llvm_base" $dir/lib/libLLVM.so
fi
# gnu-aarch64 cross: bundle the arm64 runtime deps of libLLVM so the
# toolchain is self-contained. Prefer noble builds (glibc <=2.39, runs on
# Ubuntu 24.04-class devices); sid builds need GLIBC_2.42+.
# llvm.sh puts sid debs in build/tmp and noble ones in build/tmp/noble-deps.
if [ "$arch" = "aarch64" ] && [ -z "$XTERMUX" ]; then
  depdir=$out_dir/build/tmp
  if ls $out_dir/build/tmp/noble-deps/*.deb >/dev/null 2>&1; then
    depdir=$out_dir/build/tmp/noble-deps
  fi
  tmpd=$(mktemp -d)
  for deb in $depdir/libffi8*.deb \
             $depdir/libedit2*.deb \
             $depdir/libzstd1*.deb \
             $depdir/libxml2*.deb; do
    [ -f "$deb" ] || continue
    case "$deb" in *libxml2-dev*) continue;; esac
    dpkg-deb -x "$deb" "$tmpd"
  done
  for so in "$tmpd"/usr/lib/aarch64-linux-gnu/libffi.so* \
            "$tmpd"/usr/lib/aarch64-linux-gnu/libedit.so* \
            "$tmpd"/usr/lib/aarch64-linux-gnu/libzstd.so* \
            "$tmpd"/usr/lib/aarch64-linux-gnu/libxml2.so*; do
    [ -e "$so" ] || [ -L "$so" ] || continue
    cp -a "$so" $dir/lib/
  done
  rm -rf "$tmpd"
  # noble ships libxml2.so.2 (with the old version nodes our libLLVM wants),
  # while sid-built libLLVM asks for .so.16 -> retarget when we bundled .so.2.
  if ls $dir/lib/libxml2.so.2* >/dev/null 2>&1; then
    patchelf --replace-needed libxml2.so.16 libxml2.so.2 $dir/lib/$llvm_base || true
  fi
fi
cp $(dirname $binary)/std_out/std.a $dir/lib
cp -r $cur/../src/std $dir/src

sudo=""
if command -v sudo 2>&1 >/dev/null; then
  sudo="sudo"
fi
#change llvm path to relative to toolchain
if ! command -v patchelf 2>&1 >/dev/null; then
  $sudo apt install -y patchelf
fi

if [ ! -z "$XTERMUX" ]; then
  patchelf --set-rpath '$ORIGIN/../lib:/data/data/com.termux/files/usr/lib' $dir/bin/x
  # Bundle Termux-built LLVM deps (repo termux-deps/*.deb) so the toolchain
  # does not depend on the device's rolling packages.
  # NB: libxml2 >=2.15 dropped symbol versioning, while our libLLVM wants
  # versioned xml symbols -> clear the requirements so any libxml2.so.16
  # (2.14 with versions, or 2.15 unversioned) satisfies them.
  deps_src="$cur/../termux-deps"
  if [ -d "$deps_src" ]; then
    tmpd=$(mktemp -d)
    for deb in "$deps_src"/libffi_*.deb "$deps_src"/libxml2_2*.deb "$deps_src"/zstd_*.deb; do
      [ -f "$deb" ] || continue
      dpkg-deb -x "$deb" "$tmpd"
    done
    for so in "$tmpd"/data/data/com.termux/files/usr/lib/libffi.so \
              "$tmpd"/data/data/com.termux/files/usr/lib/libxml2.so* \
              "$tmpd"/data/data/com.termux/files/usr/lib/libzstd.so*; do
      [ -e "$so" ] || [ -L "$so" ] || continue
      cp -a "$so" $dir/lib/
    done
    rm -rf "$tmpd"
  fi
  for sym in xmlFreeDoc xmlFree xmlSetGenericErrorFunc xmlReadMemory \
             xmlDocGetRootElement xmlUnlinkNode xmlFreeNode xmlCopyNamespace \
             xmlNewProp xmlStrdup xmlAddChild xmlNewDoc xmlDocSetRootElement \
             xmlDocDumpFormatMemoryEnc xmlFreeNs xmlNewNs; do
    patchelf --clear-symbol-version $sym $dir/lib/$llvm_base || echo "warn: clear $sym failed"
  done
  patchelf --replace-needed libxml2.so.2 libxml2.so.16 $dir/lib/$llvm_base || true
else
  patchelf --set-rpath '$ORIGIN/../lib' $dir/bin/x
fi

if [ $is_zip = true ]; then
  cd $out_dir
  # -y: keep symlinks as symlinks, otherwise libLLVM ships twice (118MB x2)
  zip -r -y ${name}.zip "./$name" && echo "built toolchain ${name}.zip"
else
  echo "built toolchain ${name}/"
fi
