#!/bin/bash
# setup-node.sh NAME RPC_PORT P2P_PORT KEYHEX
set -e
NAME="$1"; RPC_PORT="$2"; P2P_PORT="$3"; KEY="$4"
BASE="/opt/fnn-run/$NAME"
mkdir -p "$BASE/ckb"
printf '%s' "$KEY" > "$BASE/ckb/key"
chmod 600 "$BASE/ckb/key"
cp /opt/fnn-run/config/testnet/config.yml "$BASE/config.yml"
# add plaintext funding key path under the fiber: section
sed -i "/^fiber:/a\\  private_key_path: \"$BASE/ckb/key\"" "$BASE/config.yml"
# this node's own P2P listen port (leave bootnode /tcp/8228 entries untouched)
sed -i "s|listening_addr: \"/ip4/0.0.0.0/tcp/8228\"|listening_addr: \"/ip4/0.0.0.0/tcp/$P2P_PORT\"|" "$BASE/config.yml"
# RPC port
sed -i "s|listening_addr: \"127.0.0.1:8227\"|listening_addr: \"127.0.0.1:$RPC_PORT\"|" "$BASE/config.yml"
echo "== $NAME config =="
grep -nE "private_key_path|listening_addr|rpc_url" "$BASE/config.yml"
