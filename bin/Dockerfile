FROM debian:sid AS build

ARG host_tool
ARG target_tool
ARG version
ARG termux

ARG DEBIAN_FRONTEND=noninteractive

COPY . /home/lang
COPY "$host_tool" /home/lang/
COPY "$target_tool" /home/lang/

RUN uname -m
WORKDIR /home/lang
RUN rm -rf ./build
RUN ./bin/cross_env.sh
#RUN ./bin/cross.sh $host_tool $target_tool $version $termux
