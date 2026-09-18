{
  config,
  lib,
  pkgs,
  ...
}:
let
  root = "/mnt/data/frigate";
  # Preserve 100 GiB for the other services on this shared data filesystem.
  storageCheck = pkgs.writeShellScript "frigate-storage-check" ''
    set -eu
    ${pkgs.util-linux}/bin/mountpoint -q /mnt/data
    available=$(${pkgs.coreutils}/bin/df --output=avail -B1 /mnt/data | ${pkgs.coreutils}/bin/tail -1)
    if [ "$available" -lt 107374182400 ]; then
      echo "Frigate stopped: less than 100 GiB free on /mnt/data. Expand storage before restarting." >&2
      exit 1
    fi
  '';
in
{
  secrets.frigate.file = lib.mkDefault "/var/lib/service-secrets/frigate.env";
  services.containerAutoUpdate.skipContainers = [ "frigate" ];
  virtualisation.oci-containers.containers.frigate = {
    image = "ghcr.io/blakeblackshear/frigate:0.18.0";
    autoStart = true;
    networks = [ "backend" ];
    # Only the authenticated API; no unauthenticated API, RTSP or go2rtc ports.
    ports = [ "10.255.0.5:1030:8971/tcp" ];
    environment.TZ = "America/Chicago";
    environmentFiles = [ config.secrets.frigate.file ];
    volumes = [
      # Qualified against the pinned Frigate image; exposes CPU thread placement
      # that its stock OpenVINO configuration does not currently allow setting.
      "${./openvino_cpu.py}:/opt/frigate/frigate/detectors/plugins/openvino_cpu.py:ro"
      "${./check_camera.py}:/opt/frigate/check_camera.py:ro"
      # One-class gecko detector; training data and results in docs/gecko-tracking.md.
      "${./gecko.onnx}:/models/gecko.onnx:ro"
      "${./gecko-labelmap.txt}:/models/gecko-labelmap.txt:ro"
      "${root}/config:/config"
      "${root}/media:/media/frigate"
      "/etc/localtime:/etc/localtime:ro"
    ];
    extraOptions = [
      "--shm-size=256m"
      "--tmpfs=/tmp/cache:rw,size=536870912"
      "--memory=2g"
      "--cpus=4"
      # API availability alone missed both capture and keyframe outages.
      # Mark unhealthy without introducing automatic camera restart loops.
      "--health-cmd=python3 /opt/frigate/check_camera.py"
      "--health-interval=60s"
      "--health-timeout=30s"
      "--health-start-period=90s"
      "--health-start-interval=30s"
      "--health-retries=3"
    ];
  };

  systemd.services.docker-frigate = {
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    preStart = lib.mkBefore ''
      ${storageCheck}
      ${pkgs.coreutils}/bin/install -d -m 0700 ${root}/config ${root}/media
      ${pkgs.coreutils}/bin/install -m 0600 ${./frigate.yml} ${root}/config/config.yml
    '';
  };

  # Restrict the published authenticated port before Docker DNAT.
  networking.nftables.tables.frigate-ingress = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -311; policy accept;
        ip daddr 10.255.0.5 tcp dport 1030 ip saddr != 10.255.0.2 counter drop
      }
    '';
  };

  systemd.services.frigate-storage-guard = {
    description = "Stop camera recording before shared storage is exhausted";
    serviceConfig.Type = "oneshot";
    script = ''
      if ${pkgs.systemd}/bin/systemctl is-active --quiet docker-frigate.service; then
        if ! ${storageCheck}; then
          ${pkgs.systemd}/bin/systemctl stop docker-frigate.service
          exit 1
        fi
      fi
    '';
  };
  systemd.timers.frigate-storage-guard = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };
}
