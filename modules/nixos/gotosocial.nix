{
  config,
  kin,
  pkgs,
  ...
}:
let
  domain = "gts.zimbatm.com";
  cfg = config.services.gotosocial;
  rsyncnet = "zh6422@zh6422.rsync.net";
in
{
  services.gotosocial = {
    enable = true;
    # Forward from the apex: /.well-known/{nodeinfo,host-meta,webfinger}
    settings.account-domain = "zimbatm.com";
    settings.accounts-allow-custom-css = true;
    settings.accounts-registration-open = false;
    settings.host = domain;
    settings.instance-expose-public-timeline = true;
  };

  services.restic.backups.gotosocial = {
    initialize = true;
    passwordFile = kin.gen."user/gotosocial-restic".password;
    paths = [ "/var/lib/gotosocial" ];
    repository = "sftp:${rsyncnet}:gotosocial";
    extraOptions = [
      "sftp.command='${pkgs.sshpass}/bin/sshpass -f ${
        kin.gen."user/gotosocial-rsyncnet".password
      } ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new ${rsyncnet} -s sftp'"
    ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    timerConfig.OnCalendar = "hourly";
  };

  services.nginx.virtualHosts."${domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."= /".return = "302 $scheme://$host/@zimbatm";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
      proxyWebsockets = true;
    };
  };
}
