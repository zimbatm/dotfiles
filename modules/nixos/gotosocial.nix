{
  config,
  kin,
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
    # Key auth, not sshpass — same rsync.net account/key as kin-infra's
    # backup-offsite-creds (rsync.net has no S3, restic talks SFTP). Key
    # auth so rotation is one `kin set` instead of a rsync.net console
    # password change, and the credential never crosses the SSH password
    # negotiation. BatchMode=yes: fail fast on auth rather than prompt.
    extraOptions = [
      "sftp.command='ssh -i ${
        kin.gen."user/gotosocial-rsyncnet".key
      } -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${rsyncnet} -s sftp'"
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
