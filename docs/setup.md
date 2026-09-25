# Setup and daily operation

Run commands **inside the Ubuntu VM**, except blocks labeled Windows PowerShell.

## 1. Prepare the Ubuntu VM

Use Ubuntu Server 24.04 LTS, x86-64, in VMware Workstation with a NAT adapter.
Suggested resources: 8 vCPUs, 16 GB RAM, and 60 GB disk if the host can spare them.
These are estimates, not measured minimums. Keep the repo and Docker storage
on the VM's Linux filesystem.

Install OpenSSH Server during Ubuntu setup for access from Windows. Containers
do not require nested virtualization. See the
[Ubuntu installation guide](https://ubuntu.com/server/docs/tutorial/basic-installation/).

Find the VM's address and gateway:

```bash
ip -br address
ip route
```

For SSH/SCP, use the VMware-facing interface's IPv4 address (often `ens33`)
without the `/24` suffix. Ignore `lo` and Docker bridges.

## 2. Install tools inside Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git make
```

Install Docker Engine using the **Install using the apt repository** section of
[Docker's Ubuntu guide](https://docs.docker.com/engine/install/ubuntu/).
Use the system Docker daemon in Ubuntu, not Windows Docker Desktop. Then verify:

```bash
sudo systemctl enable --now docker
sudo docker run --rm hello-world
```

Install Containerlab using its [official installer](https://containerlab.dev/install/):

```bash
curl -fL https://get.containerlab.dev -o /tmp/containerlab-install.sh
less /tmp/containerlab-install.sh
sudo bash /tmp/containerlab-install.sh
containerlab version
```

## 3. Put the repository in Ubuntu

Replace `YOUR-USERNAME/YOUR-REPOSITORY` with the actual repository path:

```bash
mkdir -p ~/labs/containerlab-evpn-vxlan
cd ~/labs/containerlab-evpn-vxlan
git clone git@github.com:YOUR-USERNAME/YOUR-REPOSITORY.git .
```

The trailing `.` clones into the current directory, which must be empty.
For an existing clone, use `git status` and `git pull --ff-only` instead.

For SSH access, check `ls -la ~/.ssh` for an existing key first. If you need a
new key, run as your normal user and do not overwrite an existing private key:

```bash
ssh-keygen -t ed25519 -C "ubuntu-containerlab"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Accept the default filename and choose a passphrase. Add the displayed **public**
key in GitHub **Settings → SSH and GPG keys → New SSH key**, as an authentication
key. Test with `ssh -T git@github.com` and compare the first-connection fingerprint
with [GitHub's documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection).
A successful response confirms authentication but provides no shell access.
Then run the clone command.

HTTPS cloning also works - private access requires a token or credential helper.
For manual file transfers, keep LF line endings in shell scripts. Git checkout
enforces this through `.gitattributes`.

## 4. Acquire, transfer, and import cEOS

Sign in or create an account at [Arista](https://www.arista.com/en/login), then
open the [software download portal](https://www.arista.com/en/support/software-download).
Choose a cEOS64 lab archive compatible with your x86-64 VM and Containerlab.
The topology currently pins **4.36.2F**: download `cEOS64-lab-4.36.2F.tar.xz`
and its `.sha512sum` companion. ARM and vEOS VM images are different artifacts.
Arista handles access and licensing - images are not included here.

Create the destination in Ubuntu **without sudo**, so your account owns it:

```bash
mkdir -p ~/images
```

If downloading on Windows, transfer with **PowerShell**.
Replace the source paths, `YOUR-USER`, and `VM-IP`:

```powershell
scp "C:\path\to\cEOS64-lab-4.36.2F.tar.xz" "YOUR-USER@VM-IP:~/images/"
scp "C:\path\to\cEOS64-lab-4.36.2F.tar.xz.sha512sum" "YOUR-USER@VM-IP:~/images/"
```

For a destination permission error, check `ls -ld ~/images` in Ubuntu.
If created as root, fix ownership with
`sudo chown "$(id -un):$(id -gn)" "$HOME/images"`.

Back in **Ubuntu**, verify the checksum:

```bash
cd ~/images
sha512sum -c cEOS64-lab-4.36.2F.tar.xz.sha512sum
```

Proceed only after an `OK` result:

```bash
sudo docker import ~/images/cEOS64-lab-4.36.2F.tar.xz ceos:4.36.2F
sudo docker image inspect ceos:4.36.2F --format '{{.Id}}'
```

Keep the archive outside the repository. Use `docker import`, not `docker load`,
to install it in Docker's storage. See the
[Containerlab cEOS guide](https://containerlab.dev/manual/kinds/ceos/).

The imported tag must match `topology.defaults.image` in
[`lab/evpn.clab.yml`](../lab/evpn.clab.yml). For a different release, change both
the archive/tag in the commands and that single YAML value.
`image-pull-policy: Never` prevents registry pulls. Import once per Docker host -
reboots and lab teardown retain the image.

## 5. Deploy and verify

Before the first deployment, compare `ip route` and existing Docker network
subnets with [the address plan](addressing.md). If management addressing conflicts
with VMware/VPN/Docker networks, change the subnet and all six management
addresses together in the topology and documentation.

```bash
cd ~/labs/containerlab-evpn-vxlan
make deploy
make inspect
# Allow EOS to boot and BGP to converge, then run:
make verify
```

The `Makefile` provides these shortcuts:

| Shortcut | Underlying operation |
| --- | --- |
| `make deploy` | `scripts/deploy.sh`: checks tools/Docker, then `sudo containerlab deploy --topo lab/evpn.clab.yml` |
| `make inspect` | `sudo containerlab inspect --topo lab/evpn.clab.yml` |
| `make verify` | `bash scripts/verify.sh`: this project's acceptance checks |
| `make destroy` | `scripts/destroy.sh`: `sudo containerlab destroy --topo lab/evpn.clab.yml` |

Access a switch from Ubuntu:

```bash
sudo docker exec -it clab-evpn-leaf01 Cli
```

Use `enable`, then `show ip bgp summary` in EOS. Expect two peers per leaf,
four per spine. See [verification](verification.md) for checks and troubleshooting.

## Daily shutdown and restart

Docker keeps the lab running after Containerlab exits or SSH closes.

| Action | Effect |
| --- | --- |
| Close SSH / switch CLI | Lab continues running inside Ubuntu |
| `make destroy` | Removes containers and links - retains generated files and images |
| Shut down or reboot Ubuntu | Stops the fabric - retains disk files and images |
| Suspend the VM | Pauses execution - verify after resuming |
| Destroy with `--cleanup` | Also deletes generated files, including saved EOS startup configs |

Before a planned VM/PC shutdown, save desired switch changes with `write memory`
on each modified switch. Then, in Ubuntu:

```bash
cd ~/labs/containerlab-evpn-vxlan
make destroy
sudo shutdown -h now
```

Next session, start the Ubuntu VM in Workstation, log in, and run:

```bash
cd ~/labs/containerlab-evpn-vxlan
make deploy
make inspect
# After convergence:
make verify
```

Tools, the repo, and the image persist. Docker starts at boot if enabled in step 2,
but the lab must be redeployed.

**If Ubuntu rebooted with the lab deployed:** check `make inspect` and
`sudo docker ps -a`. Containers may survive without working virtual links.
Save any accessible EOS changes, then run `make destroy` **without `--cleanup`**,
`make deploy`, and `make verify`. Unsaved EOS edits may be lost after reboot.

Docker's [restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/)
control container restarts, not fabric links.
[Containerlab destroy](https://containerlab.dev/cmd/destroy/) documents teardown
and its separate cleanup option.

## Configuration persistence

| Location | Role | How it changes |
| --- | --- | --- |
| `lab/configs/*.cfg` | Version-controlled source baseline | Edit files and commit reviewed changes |
| EOS running configuration | Current switch state in memory | Configure through the EOS CLI |
| `lab/clab-evpn/<node>/flash/startup-config` | Saved startup config - Git-ignored | `write memory` in EOS |

Saved startup configs take precedence on later deployments. See
[Containerlab startup-config behavior](https://containerlab.dev/manual/nodes/#startup-config).
`write memory` does not update source files, and Git does not save running EOS
changes. Copy wanted CLI changes into source configs and review the diff.
Omit generated credentials and management settings.

To intentionally discard saved runtime state and rebuild from source:

```bash
# Deletes generated files and saved switch changes. Preserve wanted edits first.
sudo containerlab destroy --topo lab/evpn.clab.yml --cleanup
make deploy
```

`--cleanup` and `deploy --reconfigure` discard saved state - avoid them for routine
restarts. Push source edits from the editing machine and pull in the other clone.
Pulling configs does not apply them to running switches.

## Troubleshooting

| Symptom | First check |
| --- | --- |
| Image not found with policy `Never` | `sudo docker image ls ceos` - import with the topology's tag |
| Docker unavailable | `sudo systemctl status docker` and `sudo docker info` |
| Container running, EOS CLI unavailable | `sudo docker logs clab-evpn-leaf01` - allow boot time and check RAM/disk |
| cEOS boot fails | Check release compatibility, including [cgroups notes](https://containerlab.dev/manual/kinds/ceos/#cgroups-v1). |
| BGP/pings/ECMP fail | Follow [verification](verification.md) |
| Source config edits appear ignored | Check saved startup-config precedence above. |

Keep images, generated state, credentials, and raw support bundles out of Git.
Review staged changes for secrets, including edits to tracked files.
