{
  cores,
  memory,
  host,
  vmId,
  disks,
  networking,
  enableProtection,
}:
let
  toString = builtins.toString;
  
  # Detect if storage is cold (HDD) based on storage name
  isColdStorage = storage: 
    builtins.match ".*[Cc]old.*" storage != null;
  
  # Generate SCSI disk lines with appropriate optimizations
  scsiLines = builtins.concatStringsSep "\n" (
    builtins.genList (i:
      let
        disk = builtins.elemAt disks i;
        isCold = isColdStorage disk.storage;
        # SSD optimizations: discard, ssd flag, io_uring
        # HDD configuration: no discard, no ssd flag, io_uring still works
        ssdOpts = if isCold then "" else ",discard=on,ssd=1";
      in "scsi${toString i}: ${disk.storage}:vm-${toString vmId}-disk-${toString (i+1)},size=${toString disk.size}G,aio=io_uring,backup=1${ssdOpts},serial=drive-scsi${toString i}"
    ) (builtins.length disks)
  );
  
  # Generate network interface lines
  netLines = builtins.concatStringsSep "\n" (
    builtins.genList (i:
      let 
        net = builtins.elemAt networking i;
        # Build the network configuration string
        vlanPart = if net ? vlan && net.vlan != null then ",tag=${toString net.vlan}" else "";
        macPart = if net ? macAddress && net.macAddress != null then net.macAddress else "00:00:00:00:00:00";
      in "net${toString i}: virtio=${macPart},bridge=${net.bridge},firewall=${if net.firewall then "1" else "0"}${vlanPart}"
    ) (builtins.length networking)
  );
  
  firstDisk = builtins.elemAt disks 0;
  
  # qmdump maps - ONLY for drives that actually exist in the VMA file
  # scsi0 = OS disk (included in VMA)
  # scsi1, scsi2, etc = additional data disks (NOT in VMA, created empty by Proxmox)
  # efidisk0 = EFI disk (included in VMA)
  # tpmstate0 = TPM state (included in VMA)
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
machine: type=q35,enable-s3=1,enable-s4=1
memory: ${toString memory}
name: ${host}
numa: 1
onboot: 1
ostype: l26
protection: ${if enableProtection then "1" else "0"}
scsihw: virtio-scsi-single
tablet: 1
${netLines}
${scsiLines}
efidisk0: ${firstDisk.storage}:vm-${toString vmId}-disk-0,efitype=4m,pre-enrolled-keys=0,size=4M
tpmstate0: ${firstDisk.storage}:vm-${toString vmId}-disk-${toString (1 + builtins.length disks)},size=4M,version=v2.0
#qmdump#map:scsi0:drive-scsi0:${firstDisk.storage}:raw:
#qmdump#map:efidisk0:drive-efidisk0:${firstDisk.storage}:raw:
#qmdump#map:tpmstate0:drive-tpmstate0:${firstDisk.storage}:raw:
''