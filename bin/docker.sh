dir=$(dirname $0)
#run from github workflow

echo "docker.sh $1,$2,$3"

if [ ! -d "$1" ]; then
 echo "provide host toolchain" && exit 1
fi
if [ ! -d "$2" ]; then
 echo "provide target toolchain" && exit 1
fi
if [ -z "$3" ]; then
 echo "provide version" && exit 1
fi

host_tool=$1
target_tool=$2
version=$3
termux=$4

root=$(realpath "$dir/..")
image=cross

#Everything the container needs must be inside $root: that is the one directory
#bind-mounted at /home/lang. A toolchain given from elsewhere is copied in (the
#old script did the same, because the image used to bake the tree instead).
in_root(){
  local p
  p=$(realpath "$1") || exit 1
  if [[ "$p" == "$root"/* ]]; then
    echo "${p#"$root"/}"
    return
  fi
  cp -r "$1" "$root" || exit 1
  echo "$(basename "$1")"
}
host_rel=$(in_root "$host_tool")
target_rel=$(in_root "$target_tool")

#The image holds only the build environment (apt packages); the sources and
#toolchains are mounted at run time. CI caches the image as a tarball keyed on
#bin/Dockerfile + bin/apt_cross.sh, so this build is a first-run cost only.
if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build --progress=plain -t "$image" -f "$root/bin/Dockerfile" "$root" || exit 1
fi

docker run --rm --name crossc \
  -v "$root:/home/lang" -w /home/lang \
  -e XOPT -e XSTAGE -e XDEBUG \
  "$image" sh -c "bin/build.sh '$host_rel' '$version' '$target_rel'" || exit 1

#make_toolchain.sh writes the zip into the bind-mounted checkout
if [ ! -f "$root/x-toolchain-$version-aarch64.zip" ]; then
  echo "missing x-toolchain-$version-aarch64.zip after the build" && exit 1
fi

if [ "$XSAVE_IMAGE" = "true" ]; then
  docker save -o "$root/cross-image.tar" "$image" || exit 1
  #docker writes the tarball 0600 as root; the cache step reads it as the
  #runner user
  chmod 644 "$root/cross-image.tar"
fi
