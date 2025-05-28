FROM arm64v8/ubuntu:focal

COPY . /home/lang
#COPY ../x-toolchain-1.00-aarch64/ /home/lang/

#ARG DEBIAN_FRONTEND=noninteractive

RUN uname -m
WORKDIR /home/lang
RUN ./bin/build.sh ./x-toolchain-1.00-aarch64 v1.01-arm64

