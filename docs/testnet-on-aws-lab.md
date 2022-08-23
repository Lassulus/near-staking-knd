# Lab: Single node kuutamo near validator up on testnet using AWS.

- Get [NixOS EC2 AMI](https://nixos.org/download.html#nixos-amazon)
  In this demo I used N.Virginia (us-east-1): `ami-0223db08811f6fb2d` NB: Each region uses an AMI with a different name so double check that you picked the correct region on the NixOS site if the AMI doesn't show up in the AWS UI.
  
  ![image](https://user-images.githubusercontent.com/38218340/185245850-28b37993-3645-491a-b6fd-bb908737bf8d.png)
  
- Setup VM
  AWS > EC2 > AMIs > `ami-0223db08811f6fb2d` > Launch instance from AMI (we tested on c5ad.4xlarge with 300GB gp3 disk) > Launch instance
- SSH to instance

#### Edit `configuration.nix` so it is as below: `nano /etc/nixos/configuration.nix`
```nix
{ modulesPath, ... }: {
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ./kuutamod.nix];
  ec2.hvm = true;

  nix.extraOptions = ''
  experimental-features = nix-command flakes
  '';
  
  swapDevices = [{
    device = "/swapfile";
    size = 4096;
  }];
}
```

#### Add `flake.nix` file as below: `nano /etc/nixos/flake.nix`
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    kuutamod.url = "github:kuutamolabs/kuutamod";
  };
  outputs = { self, nixpkgs, kuutamod }: {
    nixosConfigurations.validator = nixpkgs.lib.nixosSystem {
      # Our neard package is currently only tested on x86_64-linux.
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        
        # Optional: This adds a our binary cache so you don't have to compile neard/kuutamod yourself.
        # The binary cache module, won't be effective on the first run of nixos-rebuild, but you can specify it also via command line like this:
        # $ nixos-rebuild switch --option  extra-binary-caches "https://cache.garnix.io" --option extra-trusted-public-keys "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" --flake /etc/nixos#validator
        self.inputs.kuutamod.nixosModules.kuutamo-binary-cache

        kuutamod.nixosModules.neard-testnet
        kuutamod.nixosModules.kuutamod
      ];
    };
  };
}

```
#### Add `kuutamod.nix` file as below: `nano /etc/nixos/kuutamod.nix`
```nix
{
  # consul is here because you can add more kuutamod nodes later and create an Active/Passive HA cluster.
  services.consul.interface.bind = "ens5";
  services.consul.extraConfig.bootstrap_expect = 1;

  kuutamo.kuutamod.validatorKeyFile = "/var/lib/secrets/validator_key.json";
  kuutamo.kuutamod.validatorNodeKeyFile = "/var/lib/secrets/node_key.json";
}
```

#### Rebuild and switch to new configuration
##### If you are wanting to use the binary cache
```console
$ nixos-rebuild switch --option  extra-binary-caches "https://cache.garnix.io" --option extra-trusted-public-keys "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" --flake /etc/nixos#validator
```
##### If not and you want compile neard and kuutamod on the machine (remember to comment out this line in `flake.nix`  `self.inputs.kuutamod.nixosModules.kuutamo-binary-cache`)
```console
$ nixos-rebuild switch --flake /etc/nixos#validator
```

#### Create keys

Follow instructions to [generate keys and install them](https://github.com/kuutamolabs/kuutamod/blob/main/docs/run-main-test-shard.md#node-keys--generating-the-active-validator-key)


You will need restart kuutamod with `systemctl restart kuutamod` so that it picks up the key. If everything
went well, you should be able to reach kuutamod's prometheus exporter url:

```consile
$ curl http://localhost:2233/metrics
# HELP kuutamod_state In what state our supervisor statemachine is
# TYPE kuutamod_state gauge
kuutamod_state{type="Registering"} 0
kuutamod_state{type="Shutdown"} 0
kuutamod_state{type="Startup"} 0
kuutamod_state{type="Syncing"} 1
kuutamod_state{type="Validating"} 0
kuutamod_state{type="Voting"} 0
# HELP kuutamod_uptime Time in milliseconds how long daemon is running
# TYPE kuutamod_uptime gauge
kuutamod_uptime 3447978
```

Once neard is synced with the network, you should see a kuutamod listed as an active validator using `kuutamoctl`:
```console
$ kuutamoctl active-validator
Name: river
```
where `Name` is the kuutamo node id.

You can view logs in the systemd journal
```console
$ journalctl -u kuutamod.service -f
Jul 17 21:43:50 river kuutamod[44389]: 2022-07-17T21:43:50.898176Z  INFO stats: # 1102053 7zgkxdDiKBoqud9DuSC47cwZ94e63BwGj1NNKs93JcLs Validator | 100 validators 29 peers ⬇ 345 kB/s ⬆ 485 kB/s 0.80 bps 0 gas/s CPU: 0%, Mem: 1.77 GB
```

---
#### Next Steps

- You can add more nodes to create an active/passive ha cluster. See [this section](https://github.com/kuutamolabs/kuutamod/blob/main/docs/run.md#multi-node-kuutamo-cluster) for more information. 

---
kuutamolabs  
[GitHub](https://github.com/kuutamolabs/kuutamod) | [Matrix](https://matrix.to/#/#kuutamo-chat:kuutamo.chat)