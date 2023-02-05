# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# You need to change this to your server IP
# server "3.22.98.114", user: "ubuntu", roles: %w{primary}

# server "54.85.162.144", user: "ubuntu", roles: %w{primary} #renec-mainnet1
# server "34.233.73.163", user: "ubuntu", roles: %w{primary} #renec-mainnet2
# server "35.169.187.80", user: "ubuntu", roles: %w{primary} #renec-mainnet3
# server "52.6.207.113", user: "ubuntu", roles: %w{primary} #renec-mainnet4
# server "34.236.126.253", user: "ubuntu", roles: %w{primary} #renec-mainnet5
# server "52.21.244.146", user: "ubuntu", roles: %w{primary} #renec-mainnet6
server "18.234.202.94", user: "ubuntu", roles: %w{primary} #renec-mainnet1-new

# testnet
# server "54.82.166.148", user: "ubuntu", roles: %w{primary} #renec-testnet1
# server "3.208.89.14", user: "ubuntu", roles: %w{primary} #renec-testnet2
# server "54.224.243.106", user: "ubuntu", roles: %w{primary} #renec-testnet2

# own validator
# server "3.222.98.114", user: "ubuntu", roles: %w{primary}
# server "54.91.199.153", user: "ubuntu", roles: %w{primary}

# You need to change this to your server IP
set :server_ip, "18.234.202.94"

set :data_full_path, "/home/ubuntu/renec-cluster"
set :renec_version, "1.9.29"

namespace :deploy do
  after :finishing, :install_all do
    on roles(:primary) do |host|
      within current_path do
        install_renec_tool_suite
        generate_keypairs
        create_renec_service
        create_renec_sys_tuner_service
        restart_renec_sys_tuner
        start_renec_validator
      end
    end
  end
end

def install_renec_tool_suite
  execute "sh -c \"$(curl -sSfL https://s3.amazonaws.com/release.renec.foundation/v#{fetch(:renec_version)}/install)\""
  execute "export PATH='/home/ubuntu/.local/share/renec/install/active_release/bin:$PATH'"

  return puts("Renec installed") if test("[ -d /home/ubuntu/.config/renec ]")
  execute "sed -i '1 i\\export PATH=\"/home/ubuntu/.local/share/renec/install/active_release/bin:$PATH\"' /home/ubuntu/.bashrc"
end

def generate_keypairs
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  return puts("Keypairs existed") if test("[ -d #{fetch(:data_full_path)}/keypairs ]")

  execute "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-identity.json"
  execute "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-vote-account.json"
  execute "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-stake-account.json"
  execute "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-withdrawer.json"
end

def install_nvme
  return puts("Nvme installed") if test("[ -d #{fetch(:data_full_path)} ]")

  # ssh to server and run lsblk to get the device name
  devices = [
    "/dev/nvme1n1",
    "/dev/nvme2n1",
    "/dev/nvme3n1",
    "/dev/nvme4n1"
  ]
  label = "renec_raid"
  execute :sudo, "mdadm --create --verbose /dev/md0 --level=0 --name=#{label} --raid-devices=#{devices.size} #{devices.join(' ')}"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/md0"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/nvme1n1"
  execute :sudo, "mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf"
  execute :sudo, "update-initramfs -u"
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  execute :sudo, "mount LABEL=#{label} #{fetch(:data_full_path)}"
  execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
  execute :sudo, "chown ubuntu:ubuntu #{fetch(:data_full_path)}"
end

# def install_storage_without_nvme
#   return puts("Storage installed") if test("[ -d #{fetch(:data_full_path)} ]")
#   execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
#   execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
#   execute :sudo, "chown ubuntu:ubuntu #{fetch(:data_full_path)}"
# end

def renec_service_definition
  template_path = File.expand_path("../../../coin-service-conf/renec.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    start_command: start_renec_validator_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_service
  upload! StringIO.new(renec_service_definition), "#{current_path}/renec.service"
  execute :sudo, "cp #{current_path}/renec.service /etc/systemd/system/"
end

def start_renec_validator_command
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6 \
    --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH \
    --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE \
    --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa \
    --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC \
    --only-known-rpc \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{fetch(:server_ip)} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --require-tower \
    --dynamic-port-range 8000-8020 \
    --entrypoint 34.233.73.163:8001 \
    --entrypoint 35.169.187.80:8001 \
    --entrypoint 52.6.207.113:8001 \
    --entrypoint 34.236.126.253:8001 \
    --entrypoint 52.21.244.146:8001 \
    --expected-genesis-hash 7PNFRHLxT9FcAxSUcg3P8BraJnnUBnjuy8LwRbRJvVkX \
    --full-rpc-api \
    --incremental-snapshots \
    --limit-ledger-size 200000000 \
    --account-index program-id \
    --account-index spl-token-owner \
    --account-index spl-token-mint"
end
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH  --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE  --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa  --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC --entrypoint 34.233.73.163:8001  --entrypoint 35.169.187.80:8001  --entrypoint 52.6.207.113:8001  --entrypoint 34.236.126.253:8001  --entrypoint 52.21.244.146:8001

# #node1
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH  --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE  --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa  --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC --entrypoint 34.233.73.163:8001  --entrypoint 35.169.187.80:8001  --entrypoint 52.6.207.113:8001  --entrypoint 34.236.126.253:8001  --entrypoint 52.21.244.146:8001
# #node3
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE  --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa  --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC --entrypoint 34.233.73.163:8001  --entrypoint 52.6.207.113:8001  --entrypoint 34.236.126.253:8001  --entrypoint 52.21.244.146:8001
# #node4
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH  --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa  --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC --entrypoint 34.233.73.163:8001  --entrypoint 35.169.187.80:8001  --entrypoint 34.236.126.253:8001  --entrypoint 52.21.244.146:8001
# #node5
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH  --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE  --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC --entrypoint 34.233.73.163:8001  --entrypoint 35.169.187.80:8001  --entrypoint 52.6.207.113:8001  --entrypoint 52.21.244.146:8001
# #node 6 need to turn of ELB
# --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6  --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH  --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE  --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa  --entrypoint 34.233.73.163:8001  --entrypoint 35.169.187.80:8001  --entrypoint 52.6.207.113:8001  --entrypoint 34.236.126.253:8001


def start_renec_validator
  execute :sudo, "systemctl enable renec.service"
  execute :sudo, "systemctl restart renec.service"
end

def renec_sys_tuner_service_definition
  template_path = File.expand_path("../../../coin-service-conf/renec-sys-tuner.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = "/home/ubuntu/.local/share/renec/install/active_release/bin/renec-sys-tuner --user ubuntu"
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_sys_tuner_service
  upload! StringIO.new(renec_sys_tuner_service_definition), "#{current_path}/renec-sys-tuner.service"
  execute :sudo, "cp #{current_path}/renec-sys-tuner.service /etc/systemd/system/"
end

def restart_renec_sys_tuner
  execute :sudo, "systemctl enable renec-sys-tuner.service"
  execute :sudo, "systemctl restart renec-sys-tuner.service"
end
