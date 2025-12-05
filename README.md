# Ouisync Mirror

Script for mirroring directories using Ouisync

## Use case

Have two entities

* _primary_: The server which has the content to be mirrored
* _mirror_: The server that mirrors the _primary_ and serves the content

The _primary_ wants to replicate content of a directory over Ouisync to one or more _mirrors_.

## Usage

The `./ouisync-mirror.sh` script will create a docker container.

```bash
$ ./ouisync-mirror.sh --help
Utility for mirroring directories using Ouisync

Usage: $(basename $0) [--help] [--host host] [--container-name name] ([--get-token ...] | [--primary ...] | [--mirror ...])

Options:
  --help

      Print this help and exit.

  --host <HOST>

      IP or ~/.ssh/config entry of a server running docker where the commands shall run.

  --container-name <NAME>

      Name of the docker container where to perform commands. Defaults to '$default_container_name'.

  --primary <STORE_DIR> <HOST_SOURCE_DIR>

      Makes this script act as a \"primary\" server, meaning that content of <HOST_SOURCE_DIR> will
      be mirrored into \"mirror\" servers. <STORE_DIR> needs to point to a directory
      where ouisync will store the repository databases.

  --mirror <TOKEN> <HOST_TARGET_DIR>

      Makes this script act as a \"mirror\" server, meaning that content of a repository
      represented by <TOKEN> will be mirrored into the <HOST_TARGET_DIR> directory.

  --get-token <TYPE>

      The the the token of a repository running in the container. Token <TYPE> must be
      'blind', 'read' or 'write'.
```

## Example

_primary_: Create new or reuse existing repo, start mirroring the `~/SourceDirectory`
directory into the repository and get the repository _read token_. The
`~/OuisyncMirrorStore` directory will be used to store the Ouisync repository
database for reuse on subsequent runs. Both directories should exist before
executing the command.

```bash
./ouisync-mirror.sh --container-name primary --primary ~/OuisyncMirrorStore ~/SourceDirectory
./ouisync-mirror.sh --get-token read
```

_mirror_: Import the repo using the _read token_ from above and mirror it into
a `~/TargetDirectory` directory.

```bash
./ouisync-mirror.sh --container-name mirror --mirror <READ_TOKEN> ~/TargetDirectory
```

## Limitations

This script is a proof-of-concept, and as such it supports only one repository.
