FROM ubuntu:latest

ARG OUISYNC_PACKAGE=https://github.com/equalitie/ouisync-app/releases/download/v0.9.2/ouisync-cli_0.9.2_amd64.deb

ENV HOME=/opt
WORKDIR $HOME

RUN apt-get update -y
RUN apt-get upgrade -y

######################################################################
###  Setup Ouisync
######################################################################
# Install dependencies.
RUN apt-get install -y lsyncd nginx wget libfuse2 libfuse3-dev fuse3 rsync

# Download ouisync package.
RUN wget -O ouisync-cli.deb $OUISYNC_PACKAGE

# Install ouisync.
RUN dpkg -i ouisync-cli.deb

# Remove the package
RUN rm ouisync-cli.deb
