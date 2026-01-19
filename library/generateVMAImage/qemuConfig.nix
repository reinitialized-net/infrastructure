{
  cores,
  memory,
  host,
  vmId,
  disks,
  networking,
}:
let
  toString = builtins.toString;
  scsiLines = builtins.concatStringsSep "\n" (
    builtins.genList (i:
      let disk = builtins.elemAt disks i;
      in "scsi${toString i}: ${disk.storage}:vm-${toString vmId}-disk-${toString (i+1)},size=${toString disk.size}G,aio=io_uring,backup=1,discard=on,iothread=1,serial=drive-scsi${toString i},ssd=1"
    ) (builtins.length disks)
  );
  firstDisk = builtins.elemAt disks 0;
in
''
acpi: 1
agent: enabled=1,freeze-fs-on-backup=1,fstrim_cloned_disks=1,type=virtio
balloon: 0
bios: ovmf
boot: order=scsi0
cores: ${toString cores}
cpu: cputype=host,hidden=0,phys-bits=host
hotplug: cpu,disk,memory,network
kvm: 1
localtime: 1
machine: type=q35,viommu=virtio
memory: ${toString memory}
name: ${host}
numa: 1
onboot: 1
ostype: l26
protection: 0
scsihw: virtio-scsi-single
tablet: 0
net0: virtio=00:00:00:00:00:00,bridge=${networking.bridge},firewall=${toString networking.firewall}${if networking ? vlan then ",tag=${toString networking.vlan}" else ""}
${scsiLines}
efidisk0: ${firstDisk.storage}:vm-${toString vmId}-disk-0,efitype=4m,pre-enrolled-keys=0,size=4M
tpmstate0: ${firstDisk.storage}:vm-${toString vmId}-disk-2,version=v2.0
#qmdump#map:scsi0:drive-scsi0:${firstDisk.storage}:raw:
#qmdump#map:efidisk0:drive-efidisk0:${firstDisk.storage}:raw:
#qmdump#map:tpmstate0:drive-tpmstate0:${firstDisk.storage}:raw:
''