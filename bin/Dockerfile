FROM arm64v8/ubuntu:focal

COPY ./std.a /home/std.a
COPY ./x-1.6-arm64.a /home/x-1.6-arm64.a

ARG DEBIAN_FRONTEND=noninteractive

# Basic apt update
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install llvm-16 clang-16
 
