FROM ubuntu:latest
WORKDIR /home/ubuntu

# TODO: Using the version and timestamp in the file name makes it impossible to
# always download the latest ouisync version.
ARG OUISYNC_PACKAGE=https://github.com/equalitie/ouisync-app/releases/download/v0.8.3-production/ouisync-cli_0.8.3-20241114150353.2ebaebde_amd64.deb
# Useful when there are other devices on the same local network to seed with,
# possible values are `true` and `false`.

ENV HOME=/home/ubuntu

RUN apt-get update -y

# For debugging
RUN apt-get install -y vim tmux less

######################################################################
###  Setup Ouisync
######################################################################
# Install dependencies.
RUN apt-get install -y wget libfuse2 libfuse3-dev fuse3

# Download ouisync package.
RUN wget -O ouisync-cli.deb $OUISYNC_PACKAGE

# Install ouisync.
RUN dpkg -i ouisync-cli.deb

# Remove the package
RUN rm ouisync-cli.deb

######################################################################
###  Setup Nginx
######################################################################
RUN apt-cache search nginx
RUN apt-get install -y nginx

COPY aux/nginx.conf /etc/nginx/

######################################################################
###  Setup working directories
######################################################################

COPY creator $HOME/creator
RUN chown ubuntu:ubuntu creator -R

# The seeder needs to run as the `ubuntu` user so that nginx can access
# the mounted directories.
COPY seeder $HOME/seeder
RUN chown ubuntu:ubuntu seeder -R

######################################################################
