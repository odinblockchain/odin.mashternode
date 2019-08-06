# ODIN.MASHternode

This MASHternode controller is based off the original *Nodemaster* by Github User Masternodes for use with PIVX. [Source](https://github.com/masternodes/vps).

------

The **Nodemaster** scripts is a collection of utilities to manage, setup and update masternode instances.

I am quite confident this is the single best and almost effortless way to setup different crypto masternodes, without bothering too much about the setup part.

## Installation

SSH to your VPS and clone the Github repository:

```
git clone https://github.com/odinblockchain/odin.mashternode.git && cd odin.mashternode/vps
```

Install & configure your desired master node with options:

```
./install.sh -p odin
```

```
./install.sh -p odin -n 4/6
```

#### Install & configure 4 ODIN masternodes:

```
./install.sh -p odin -c 4
```

#### Update daemon of previously installed ODIN masternodes:

```
./install.sh -p odin -u
```

#### Install 6 ODIN masternodes with the git release tag "tags/??"

```
./install.sh -p odin -c 6 -r "tags/??"
```

#### Wipe all ODIN masternode data:

```
./install.sh -p odin -w
```

#### Install 2 ODIN masternodes and configure sentinel monitoring:

```
./install.sh -p odin -c 2 -s
```

## Options

The *install.sh* script support the following parameters:

| Long Option    | Short Option | Values                 | Description                                             |
| :------------- | :----------- | ---------------------- | ------------------------------------------------------- |
| `--help`       | `-h`         |                        | Print help info                                         |
| `--project`    | `-p`         | project (e.g., "odin") | Shortname for project                                   |
| `--net`        | `-n`         | `"4" / "6"`            | IP Type for Masternode *(ipv6 default)*                 |
| `--release`    | `-r`         | `"tags/vx.x.x"`        | A specific git tag/branch *(latest default)*            |
| `--count`      | `-c`         | `Number`               | Amount of masternodes to be configured                  |
| `--update`     | `-u`         |                        | Update specified Masternode Daemon, combine with `-p`   |
| `--sentinel`   | `-s`         |                        | Install and configure sentinel for node monitoring      |
| `--wipe`       | `-w`         |                        | Uninstall & Wipe all Masternode data, combine with `-p` |
| `--startnodes` | `-x`         |                        | Starts Masternode(s) after installation                 |

## Troubleshooting the masternode on the VPS

If you want to check the status of your masternode, the best way is currently running the cli e.g. for $ODIN via

```
/usr/local/bin/odin-cli -conf=/etc/masternodes/odin_n1.conf getinfo
```
