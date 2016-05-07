# mesoscloud-do

[![Join the chat at https://gitter.im/mesoscloud/mesoscloud](https://badges.gitter.im/mesoscloud/mesoscloud.svg)](https://gitter.im/mesoscloud/mesoscloud?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Create a mesoscloud on DigitalOcean.

## Getting Started

### 1

Generate a DigitalOcean Personal Access Token and update your environment.

*1.1*

https://cloud.digitalocean.com/settings/applications#access-tokens

*1.2*

```
export DIGITALOCEAN_ACCESS_TOKEN=<access-token>
```

Note that you can regenerate your access token at any time if you prefer not to save a copy.

### 2

Generate an SSH Key if you do not already have one.

```
test -e ~/.ssh/id_rsa || ssh-keygen -f ~/.ssh/id_rsa -N ''
```

### 3

You can clone mesoscloud-do now if you haven't already.  If you prefer, you can run the latest version of  mesoscloud.sh directly from github.

```
git clone git@github.com:mesoscloud/mesoscloud-do.git
cd mesoscloud-do
./mesoscloud.sh
```

OR

```
curl -fLsS https://raw.githubusercontent.com/mesoscloud/mesoscloud-do/master/mesoscloud.sh | sh
```

### 4

Take a look at `mesoscloud.cfg.current` in your current directory, this file represents the current configuration state and will be overwritten each time you run `mesoscloud.sh`.  If you want to persist configuration without relying solely on environment variables then you can create a `mesoscloud.cfg` file with content based on the values in `mesoscloud.cfg.current`.

Note:

- you may want to add `mesoscloud.cfg.current` to your `.gitignore` file to avoid accidentally committing secrets to your Git repo.
- if you are going to add your `mesoscloud.cfg` to source control consider *not* storing your digitalocean access token in `mesoscloud.cfg` and requiring that it be set via an environment variable

### 5

At this point you may choose to point a domain at one or more of your nodes using a wildcard DNS record.

https://cloud.digitalocean.com/domains

![docs/screen-1.png](docs/screen-1.png)

## Commands

### app

e.g.

```
$ ./mesoscloud.sh app < apps/foo.json
```

### job

e.g.

```
$ ./mesoscloud.sh job < jobs/foo.json
```

### rsync

e.g.

```
$ ./mesoscloud.sh rsync -av data foo-1:
building file list ... done
data/
data/file1
data/file2
data/file3

sent 3146368 bytes  received 92 bytes  51161.95 bytes/sec
total size is 3145728  speedup is 1.00
```

```
$ ./mesoscloud.sh rsync -av data foo-1:
building file list ... done

sent 124 bytes  received 20 bytes  41.14 bytes/sec
total size is 3145728  speedup is 21845.33
```

```
$ rm -rf data
```

```
$ ./mesoscloud.sh rsync -av foo-1:data .
receiving file list ... done
data/
data/file1
data/file2
data/file3

sent 88 bytes  received 3146742 bytes  273637.39 bytes/sec
total size is 3145728  speedup is 1.00
```

```
$ ./mesoscloud.sh rsync -av foo-1:data .
receiving file list ... done

sent 16 bytes  received 118 bytes  38.29 bytes/sec
total size is 3145728  speedup is 23475.58
```

### sftp

sftp can be used to securely transfer files to and from your mesoscloud.

e.g.

```
$ echo put data | ./mesoscloud.sh sftp foo-1
Connected to 104.131.34.41.
sftp> put data
Uploading data to /root/data
data                                                        100% 1024KB 256.0KB/s   00:04
```

```
$ ./mesoscloud.sh sftp foo-1
Connected to 104.131.34.41.
sftp> get data
Fetching /root/data to data
/root/data                                                  100% 1024KB 128.0KB/s   00:08
sftp>
```

## Tutorials

### Using mesoscloud-do to create a mesoscloud on DigitalOcean

[![asciicast](https://asciinema.org/a/25420.png)](https://asciinema.org/a/25420)
