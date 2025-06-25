# Ouisync Web

Script for distributing web content over Ouisync.

## Use case

Have two entities

* _creator_: Web content creator
* _server_: HTTP Web Server

The _creator_ has web content which they want to transfer over Ouisync to the _server_ for it to serve.

## Usage

The `./ouisync-web.sh` script will create a docker container. Depending on
whether it's used by the _creator_ or the _server_ differnt subset of the flags
should be used.

```bash
$ ./ouisync-web.sh --help
Script for serving web site shared over Ouisync"
Usage: $(basename $0) [--container-name name] [--get-token access] [--start] [--create] [--import token] [--upload dir] [--serve]"
Options:"
  --container-name name    Name of the docker container where to perform commands. Defaults to 'ouisync-web'"
  --start                  Start the container and Ouisync inside it"
  --create                 Create a new repository"
  --upload dir             Upload content of dir into the repository"
  --get-token acces        Get access token of a previously created repository. Must be 'blind','read' or 'write'"
  --import token           Import an existing repository"
  --serve                  Start serving content of the repository over http on port 8080"
```

## Example

_creator_: Create a new repo, upload content to it and create `read_token` for the _server_.

```bash
$ # Start the Docker container and ouisync inside it
$ ./ouisync-web.sh --start
$ # Create ouisync repository. Only one repository is supported, see "Limitations"
$ ./ouisync-web.sh --create
$ # Create web content
$ mkdir /tmp/ouisync-web
$ echo "Hello from Ouisync Web" > /tmp/ouisync-web/index.html
$ # Upload content to the repository, call this any time the web content changes
$ ./ouisync-web.sh --upload /tmp/ouisync-web
$ # Get the read token to be used on the server
$ read_token=$(./ouisync-web.sh --get-token read)
```

_server_: Import the repo using the `read_token` from above and start serving it on port 8080

```bash
$ # Start the Docker container and ouisync inside it
$ ./ouisync-web.sh --start
$ # Import the previously created repository using the `read_token`
$ ./ouisync-web.sh --import $read_token
$ # Start serving the web content
$ ./ouisync-web.sh --serve
```

## Warnings

### Upload only when synced

In the above example we have one _creator_ who always has the latest version of
the repository and thus is "always synced". In theory we could have multiple
_creators_, or the same _creator_ may wish to upload the web content from
another device. In such cases it is important for the _creator_ to always
`--upload` new content _on top_ of the latest content version.

Not doing so would create divergent versions which Ouisync would resolve by
merging them together. Meaning

* Files removed from one version but not the other would re-appear
* Files present in both versions would be renamed (`.<hash-suffix>` would be
  appended to their names)

To avoid this, the _creator_ may do something like this:

```bash
$ # Start the Docker container and ouisync inside it
$ ./ouisync-web.sh --start
$ # Import the repository in write mode (--get-token write)
$ ./ouisync-web.sh --import $write_token
$ # Serve the content locally to check we have the latest version
$ ./ouisync-web.sh --serve
$ # Once we have the latest version, we can start uploading new content
$ ./ouisync-web.sh --upload /tmp/ouisync-web
```

### Remember to keep the _write token_

The _creator_ should save the write token of the repository (`--get-token
write`). If it's lost and the container where we have write access to the
repository (`--create` or `--import write_token`) is deleted, a new repository
will need to be created and the server will need to be re-initiated with the
new _read token_.

### Keep the __write token__ safe

_Anyone_ who has the _write token_ can modify the repository.

### Only send the _read token_ to the server

The _server_ only needs the _read token_. It would work with _write token_ as
well, but if the _server_ is compromised, the attacker could retrieve the
_write token_ and remove or add malicious content to the repo.

## Limitations

This script is a proof-of-concept, and as such it supports only one repository.
It shouldn't be too hard to support for multiple repos and serving the on
different ports, but I wanted to avoid this complexity for the first iteration.
