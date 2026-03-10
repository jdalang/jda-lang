FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    nasm \
    binutils \
    make \
    xxd \
    file \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /jda

CMD ["/bin/bash"]
