FROM debian:sid AS build

ARG host_tool
ARG target_tool
ARG termux

ARG DEBIAN_FRONTEND=noninteractive

COPY . /home/lang
#COPY "$host_tool" /home/lang/
#COPY "$target_tool" /home/lang/

WORKDIR /home/lang
RUN rm -rf ./build ./cpp_bridge/build
RUN XTERMUX="$termux" XTMP=./build/tmp ./bin/apt_cross.sh
