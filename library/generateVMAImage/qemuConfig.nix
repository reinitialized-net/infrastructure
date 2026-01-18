{
  cores,
  memory,
  host,
  vmId,
  disk,
  networking,
}:
let
  toString = builtins.toString;
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
  machine: type=q35,enable-s3=1,enable-s4=1,viommu=virtio
  memory: ${toString memory}
  name: ${host}
  numa: 1
  onboot: 1
  ostype: l26
  protection: 0
  scsihw: virtio-scsi-single
  tablet: 0
  net0: virtio=00:00:00:00:00:00,bridge=${networking.bridge},firewall=${toString networking.firewall}${if networking ? vlan then ",tag=${toString networking.vlan}" else ""}

  scsi0: ${disk.storage}:vm-${toString vmId}-disk-1,size=${toString disk.size}G,aio=io_uring,backup=1,discard=on,iothread=1,serial=drive-scsi0,ssd=1
  efidisk0: ${disk.storage}:vm-${toString vmId}-disk-0,efitype=4m,pre-enrolled-keys=0,size=4M
  tpmstate0: ${disk.storage}:vm-${toString vmId}-disk-2,version=v2.0

  # Proxmox qmdump mapping:
  # - For block-backed storages (zfspool zvol, LVM-thin), restore streams must be RAW bytes.
  # - Keep `efidisk0` (OVMF VARS) and `tpmstate0` raw for compatibility.
  #qmdump#map:scsi0:drive-scsi0:${disk.storage}:raw:
  #qmdump#map:efidisk0:drive-efidisk0:${disk.storage}:raw:
  #qmdump#map:tpmstate0:drive-tpmstate0:${disk.storage}:raw:
''