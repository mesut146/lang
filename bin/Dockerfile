#Environment-only image for the two cross builds. The sources (and the
#downloaded toolchains) are bind-mounted at run time:
#  docker run -v $PWD:/home/lang ...
#so the image does not depend on the checkout and CI can cache it across
#commits (cross-image.tar in .github/workflows/main.yml).
#bin/Dockerfile.dockerignore keeps the build context to bin/apt_cross.sh.
#
#The old image ran `COPY . /home/lang`, which baked the whole tree -- the
#~2.5GB Android NDK included -- into one layer; docker then spent ~2 minutes
#per run exporting and unpacking those layers around a build of ~90 seconds.
#Keeping the environment separate makes the image small (~900MB) and cheap to
#save/load. The NDK is not part of it either: it is arch-independent, but it is
#only needed by the termux build and its zip downloads fast, so apt_cross.sh
#fetches it at run time when XTERMUX is set.
FROM debian:sid

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /opt/env
COPY bin/apt_cross.sh /opt/env/bin/apt_cross.sh
RUN ./bin/apt_cross.sh
#nothing to install at run time: termux.sh skips apt_cross.sh when this is set
ENV XENV_READY=1

WORKDIR /home/lang
