# mesoscloud-do

Create a mesoscloud on DigitalOcean.

## Getting Started

### 1

https://cloud.digitalocean.com/settings/applications#access-tokens

### 2

Warning!  Be careful not to overwrite an existing key

```
test -e ~/.ssh/id_rsa || ssh-keygen -f ~/.ssh/id_rsa -N ''
```

### 3

```
git clone git@github.com:mesoscloud/mesoscloud-do.git
cd mesoscloud-do
```

### 4

```
export DIGITALOCEAN_ACCESS_TOKEN=...
./mesoscloud.sh
```

### 5

https://cloud.digitalocean.com/domains

### What does it look like?

[![asciicast](https://asciinema.org/a/4222yk4kw06tryekychqqnczo.png)](https://asciinema.org/a/4222yk4kw06tryekychqqnczo)

## What's Next?

### ssh

e.g.

```
$ ./mesoscloud.sh ssh nodes hostname
node-1
node-3
node-2
```
