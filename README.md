# LusoCryptoLabs Fiber node

The configuration and the rebuild recipe for the LusoCryptoLabs routing node on the
Fiber Network (Nervos CKB). It runs permanently on the VPS at `/opt/fnn-run/LCL`.

**What is here and what is deliberately not.** The config, the systemd unit and the
setup script are here. The **keys and the channel state are not, and must never be.**
The keys for the obvious reason. The channel state for a less obvious one: restoring a
stale copy and publishing an old commitment transaction is how a node in this family
gets slashed by its own counterparty, so a version-controlled copy of it is not a
backup, it is a loaded gun. Those live in the encrypted off-site backup
(`BACKUP_EXTRA_PATHS` on the control plane, pushed to R2 through an rclone crypt
remote). Rebuilding needs this repo **and** that backup; neither alone is enough.

## What it is

| | |
|---|---|
| identity | `03cd8c4b3e7ab065d514a1ad26e0e66f5e81b0adfaadd1896e3cdbf3cbebc2fab1` |
| announced | `/ip4/82.29.173.3/tcp/8348/p2p/QmXWMttjTWihvGXFsGqTJH8oE2rsrtbbtQwmz3DUj2yCct` |
| ports | RPC `127.0.0.1:8347`, p2p `0.0.0.0:8348` |
| chain | testnet |
| fnn | 0.8.1 |
| fee | 500 millionths (0.05%) |

## Building the node from nothing

```sh
# 1. keys. fnn will NOT create these and panics on first start without them.
mkdir -p /opt/fnn-run/LCL/{ckb,fiber}
printf '%s' "<64 hex chars, the on-chain funding key>" > /opt/fnn-run/LCL/ckb/key
head -c 32 /dev/urandom > /opt/fnn-run/LCL/fiber/sk   # the node's identity, keep it
chmod 600 /opt/fnn-run/LCL/ckb/key /opt/fnn-run/LCL/fiber/sk

# 2. config and unit
cp config.yml /opt/fnn-run/LCL/config.yml
cp lcl-fnn.service /etc/systemd/system/
ufw allow 8348/tcp
systemctl daemon-reload && systemctl enable --now lcl-fnn

# 3. the funding key's address needs CKB before any channel can be opened.
```

`FIBER_SECRET_KEY_PASSWORD` must be set in `/etc/trickle-fnn.env`, which the unit reads.

**Add `/opt/fnn-run/LCL` and the unit to `BACKUP_EXTRA_PATHS` on the control plane.**
Nothing discovers a new node directory on its own; the node built on 2026-09-05 was in
no backup at all until it was added by hand.

## Being a router is a question of topology, not configuration

This is the part worth reading, because the first attempt got it wrong.

**Connect to the two best-connected nodes and you have built nothing.** A router earns
by being on the shortest path between two nodes. If your two peers already have a direct
channel with each other, every payment takes that hop instead of your two, and you are a
redundant parallel edge that will never be chosen. That is exactly what happened here:
the first two channels went to the biggest hub and to CkbaNode-1, **and those two were
already connected to each other.**

The fix is to pick peers that are **not** connected and share **no** common neighbours,
so the only way between them is through you. A third channel to `bootnodesgp` did that,
and it is checkable rather than hopeful:

```
CkbaNode-1 and bootnodesgp directly connected: False
their common neighbours (every 2-hop path between them): ['LusoCryptoLabs']
```

Two more things that decide whether a router works:

* **Both directions need balance.** Capacity in a direction is the smaller of the
  inbound on the channel money arrives by and the outbound on the channel it leaves by.
  A channel you funded yourself is all outbound and can only send. **Inbound is not
  something you request, you make it by spending outwards**, which moves balance to the
  counterparty's side of your own channel.
* **The graph is smaller than it looks.** The dominant hub advertises 547 channels but
  has only **6 distinct peers**: hundreds of parallel channels to the same handful of
  operators. Count peers, not channels.

## Operational gotchas, all paid for once

* `open_channel` takes **`pubkey`**. Not `peer_id`, not `peer_pubkey`.
* **Two `open_channel` calls back to back: the second fails.** It tries to spend the
  change of the first before it has confirmed (`capacity not enough`). Wait for
  `ChannelReady`.
* `announce_listening_addr: true` on its own announces **`0.0.0.0`**, which nobody can
  dial. A router needs an explicit `announced_addrs` carrying the public IP.
* Amounts are hex and **leading zeros are rejected**: `0x0df8475800` is refused,
  `0xdf8475800` is the same number and is accepted.
* `open_channel` fails with "feature not found, waiting for peer to send Init message"
  when the handshake has not finished. Confirm the peer is in `list_peers` first.
* fnn has a **built-in watchtower**, on by default at 60 seconds
  (`--fiber-disable-built-in-watchtower [default: false]`). It only protects while the
  node is running, which is the argument for `Restart=always`.

## Moving to mainnet

Same recipe: change `chain:` to `mainnet`, point `ckb.rpc_url` at a mainnet node, swap
the `scripts:` section for the mainnet script deployment, and fund the wallet with real
CKB. Understand first that routing fees are only money on mainnet, that no fnn release
declares mainnet readiness, and that the watchtower protects only while the node is up.
