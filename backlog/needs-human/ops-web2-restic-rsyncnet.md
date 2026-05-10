# ops: web2 restic-backups-gotosocial — rsync.net SFTP auth failing

**needs-human** — likely a credential rotate (`kin set`) or rsync.net
account-side change. Drift's non-root probe gets the journal but can't
read `/run/kin/user/gotosocial-rsyncnet/password` to test the leg.

## What

`restic-backups-gotosocial.service` fails hourly (every cycle in the
journal window — 37 `Fatal:` lines = ~18 cycles, last @ 2026-05-10
08:00). Pre-start (`restic snapshots` then `restic init …`) dies with:

```
Fatal: unable to open repository at sftp:zh6422@zh6422.rsync.net:gotosocial:
  unable to start the sftp session, error: error receiving version
  packet from server: server unexpectedly closed connection: unexpected EOF
```

The SSH connection establishes (the server *closes* it — no DNS or TCP
error), but the SFTP subsystem never negotiates. `unexpected EOF`
before the version packet is the rsync.net signature for **password
auth rejected** under the BatchMode=no/sshpass path
(`modules/nixos/gotosocial.nix:29-31`):

```nix
"sftp.command='${pkgs.sshpass}/bin/sshpass -f ${
  kin.gen."user/gotosocial-rsyncnet".password
} ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new ${rsyncnet} -s sftp'"
```

**Survived gen-26 deploy + reboot (May-9 21:06)** — failure pattern
identical at 20:00 (pre-reboot, gen-25), 21:00 (pre-reboot), 22:00
(post-reboot, gen-26), …, 08:00. So it's not config-staleness; the
secret value or the remote account is wrong.

## Why

gotosocial's only off-site backup. The repo at `zh6422.rsync.net:gotosocial`
may not exist (pre-start tries `init` after `snapshots` fails) — if the
account was reset or password rotated on the rsync.net side, web2 has
been backing up nowhere since at least May-9.

## How much

5–10 min triage from a machine that can read the secret:

```sh
# does the password leg auth?
kin ssh root@web2 -- 'sshpass -f /run/kin/user/gotosocial-rsyncnet/password \
  ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new \
  zh6422@zh6422.rsync.net ls'
# if rejected: rotate the password on rsync.net, then
kin set user/gotosocial-rsyncnet/_shared/password
kin gen && kin deploy web2
```

Likely outcomes (ranked):
- rsync.net password rotated/expired → `kin set` the new one, redeploy.
- rsync.net account `zh6422` disabled / over quota → fix on the rsync.net
  console; no nix change.
- rsync.net dropped password auth for SFTP → switch
  `modules/nixos/gotosocial.nix` to a keypair (`extraOptions` `-i`),
  add a `kin.gen` keypair generator. File `bug-` if so.

## History

- gen-25 (Apr-24) carried this failure too (drift @ 80a9212, 6753fd8).
- gen-26 deploy + reboot (May-9 21:06) did NOT clear it — ruling out
  secret-not-mounted and unit-config staleness.
- Companion `ops-web2-acme-renew.md` *was* cleared by the same deploy
  and is closed.
- **gen-27 deploy + reboot (May-10 ~12:13) — DO NOT CLOSE on the
  false-clean.** `kin status` reports `FAILED -` and `is-failed` says
  `inactive` immediately after the reboot, but the journal shows the
  same `Fatal: …unexpected EOF` at 12:00 UTC (one minute before
  reboot), and the deploy didn't touch `gotosocial.nix` or the secret.
  Reboot reset the unit's FAILED flag; the next timer fire is 13:00
  UTC. Re-probe after that before considering this resolved.
  (drift @ d9ac7f1, 2026-05-10)
- **False-clean CONFIRMED: 13:00 cycle FAILED.** First post-reboot
  timer fire at 13:00:01 UTC ran and died the same way —
  `Fatal: unable to open repository at sftp:zh6422@zh6422.rsync.net:gotosocial:
  … server unexpectedly closed connection: unexpected EOF`. `kin status
  web2` is back to `✗`. gen-27 deploy did not fix this — still a
  credential/account problem on the rsync.net leg, not a nix-side bug.
  (drift @ 4868b89, 2026-05-10)

Filed by drift @ 87a370f, 2026-05-10.
