# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  ghaf,
  nixos-hardware,
  nixpkgs,
}: {
  deviceName,
  networkPciAddr,
  networkPciVid,
  networkPciPid,
  gpuPciAddr,
  gpuPciVid,
  gpuPciPid,
  usbInputVid,
  usbInputPid,
}:
with nixpkgs; let
  netvmExtraModules = [
    {
      microvm.devices = lib.mkForce [
        {
          bus = "pci";
          path = networkPciAddr;
        }
      ];

      # For WLAN firmwares
      hardware.enableRedistributableFirmware = true;

      networking.wireless = {
        enable = true;

        #networks."ssid".psk = "psk";
      };
    }
  ];
  guivmExtraModules = [
    {
      microvm.qemu.extraArgs = [
        "-usb"
        "-device"
        "usb-host,vendorid=0x${usbInputVid},productid=0x${usbInputPid}"
      ];
      microvm.devices = [
        {
          bus = "pci";
          path = gpuPciAddr;
        }
      ];
    }
    ({pkgs, ...}: {
      ghaf.graphics.weston.launchers = [
        {
          path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.5 chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
          icon = "${pkgs.weston}/share/weston/icon_editor.png";
        }

        {
          path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.6 gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
          icon = "${pkgs.weston}/share/weston/icon_editor.png";
        }

        {
          path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.7 zathura";
          icon = "${pkgs.weston}/share/weston/icon_editor.png";
        }
      ];
    })
  ];
in {
  nixosConfigurations.${deviceName} = ghaf.nixosConfigurations.generic-x86_64-debug.extendModules {
    modules = [
      (ghaf + "/modules/virtualization/microvm/guivm.nix")
      (ghaf + "/modules/virtualization/microvm/appvm.nix")
      ({
        pkgs,
        lib,
        ...
      }: {
        services.udev.extraRules = ''
          # Add usb to kvm group
          SUBSYSTEM=="usb", ATTR{idVendor}=="${usbInputVid}", ATTR{idProduct}=="${usbInputPid}", GROUP+="kvm"
        '';
        ghaf = {
          profiles.applications.enable = lib.mkForce false;
          virtualization.microvm.netvm = {
            extraModules = netvmExtraModules;
          };
          virtualization.microvm.guivm = {
            enable = true;
            extraModules = guivmExtraModules;
          };
          virtualization.microvm.appvm = {
            enable = true;
            vms = [
              {
                name = "chromium";
                packages = [pkgs.chromium];
                ipAddress = "192.168.101.5/24";
                macAddress = "02:00:00:03:03:05";
                ramMb = 3072;
                cores = 4;
              }
              {
                name = "gala";
                packages = [pkgs.gala-app];
                ipAddress = "192.168.101.6/24";
                macAddress = "02:00:00:03:03:06";
                ramMb = 1536;
                cores = 2;
              }
              {
                name = "zathura";
                packages = [pkgs.zathura];
                ipAddress = "192.168.101.7/24";
                macAddress = "02:00:00:03:03:07";
                ramMb = 512;
                cores = 1;
              }
            ];
            extraModules = [{}];
          };
        };
      })

      {
        boot.kernelParams = lib.mkForce [
          "intel_iommu=on,igx_off,sm_on"
          "iommu=pt"

          # TODO: Change per your device
          # Passthrough Intel WiFi card 8086:02f0
          # Passthrough Intel Embedded GPU 8086:9b41
          "vfio-pci.ids=${networkPciVid}:${networkPciPid},${gpuPciVid}:${gpuPciPid}"
        ];
      }
    ];
  };
  packages.x86_64-linux.${deviceName} = self.nixosConfigurations.${deviceName}.config.system.build.${self.nixosConfigurations.${deviceName}.config.formatAttr};
}
