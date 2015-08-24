# mesoscloud-do

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

Warning!  Be careful not to overwrite an existing key

```
test -e ~/.ssh/id_rsa || ssh-keygen -f ~/.ssh/id_rsa -N ''
```

### 3

You can clone mesoscloud-do now if you haven't already.  You can also run a shell one-liner to execute the latest version of mesoscloud.sh directly.

```
git clone git@github.com:mesoscloud/mesoscloud-do.git
cd mesoscloud-do
./mesoscloud.sh
```

**OR**

```
curl -fLsS https://raw.githubusercontent.com/mesoscloud/mesoscloud-do/master/mesoscloud.sh | sh
```

### 4

https://cloud.digitalocean.com/domains

![docs/screen-1.png](docs/screen-1.png)

### Screen casts

#### Using mesoscloud-do to create a mesoscloud on DigitalOcean

<script type="text/javascript" src="https://asciinema.org/a/25420.js" id="asciicast-25420" async></script>
