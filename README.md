Use the `run-docker.sh` script to start docker with ouisync and nginx installed.

Then you can do two things:

1. Create a repository and put files into it
2. Start seeding existing repository over ouisync and nginx

Use create a repository use the script `~/creator/create-repo.sh`. When you run it
it'll create a new repo, mount it to `~/creator/ouisync/www`. It'll
will also start seeding it right a way.

The script will halt so you'll need to connect to docker from another terminal
or use `tmux` to copy files to the mounted folder.

To start serving and seeding the repo use the scrit in `~/seeder/seed-repo.sh`.
The first and only argument to the script is the repository token that the
`create-repo.sh` prints out.  Make sure to use the READ token. The WRITE token
would also work but it's a secret and we don't want it on the seeder machines
(although for testing feel free to use that as well).

In short, in the docker container, use something like this:

Create a repo:

```bash
./creator/create-repo.sh # Leave this running
```

That will spit out the tokens, copy the READ token to clipboard.

Open another terminal and write something to the repo

```bash
docker run -it <CONTAINER ID> bash
echo "Hello Deflect/Ouisync/451" > ./creator/ouisync/www/index.html
# Feel free to close this now and close the terminal
```

Open another terminal and start the seeder

```bash
docker run -it <CONTAINER ID> bash
./seeder/seed-repo.sh <THE_TOKEN_FROM_THE_CREATE_REPO_STEP> # Leave this running
```

Start nginx

```bash
docker run -it <CONTAINER ID> bash
nginx # Feel free to close after this
```

Finally, go to your browser and type "localhost:8080" to the URL bar.
