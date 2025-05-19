FROM arm64v8/ubuntu:focal

COPY .. /home
COPY ../x-toolchain-1.00-aarch64 /home/lang

ARG DEBIAN_FRONTEND=noninteractive

RUN uname -m
RUN ./build.sh ../x-toolchain-1.00-aarch64 v2

