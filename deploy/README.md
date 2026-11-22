# Deploy

| Folder | Use |
| --- | --- |
| `local/` | Docker Compose for development on a laptop: server, PostgreSQL, LiveKit. |
| `production/` | The real server in Uzbekistan. **No Docker.** |

## Why production does not use Docker

The production machine (Ubuntu 24.04, 2 cores, 4 GB RAM) also runs a live
store app behind nginx, PostgreSQL 16 and ufw. Docker writes its own
iptables rules, and published container ports skip ufw, which could expose
ports on a machine that serves a production app. So production uses plain
systemd services under a separate `mafia` user, with memory and CPU caps,
behind the existing nginx and firewall.

## What production adds to the server

Nothing here is applied without the owner's yes. Each step is additive and
can be undone by removing what it added.

1. A system user `mafia` and folders `/opt/mafia`, `/etc/mafia`.
2. A separate role and database on the existing PostgreSQL 16
   (`postgres.sql`). The store app's databases are not touched.
3. The game server: one native binary (built by CI, no Dart SDK needed on
   the server), run by `systemd/mafia-server.service`, listening on
   127.0.0.1:8080 only. Memory capped at 512 MB. Before each start,
   systemd runs the `migrate` binary next to it, which applies any new
   file in `migrations/` once.
4. LiveKit: the official single binary, run by
   `systemd/mafia-livekit.service`, signalling on 127.0.0.1:7880 only.
   Memory capped at 1 GB.
5. nginx: one new file (`nginx/mafia.conf`, installed as
   `zz-mafia.conf`) for two new hostnames, `api.` and `video.`. The
   certificate comes from certbot's webroot mode, so certbot never edits
   the store's nginx file: first enable only the port 80 block, then
   `certbot certonly --webroot -w /var/www/mafia-acme --cert-name mafia
   -d api.<domain> -d video.<domain> --deploy-hook "systemctl reload nginx"`,
   then the full file. Always `nginx -t` and `systemctl reload nginx`,
   never a restart.
6. ufw: the only new openings are for video media,
   `ufw allow 7881/tcp` and `ufw allow 50000:50100/udp`.

Undo: `systemctl disable --now mafia-server mafia-livekit`, remove the
nginx file and the two ufw rules, `certbot delete --cert-name mafia`,
`DROP DATABASE mafia; DROP ROLE mafia;`.

## Signing in before Eskiz SMS is set up

Keep `SMS_PROVIDER=console` and list a few test numbers with fixed codes in
`AUTH_TEST_PHONES` (`+998900000001=<6 digits>,...`). No SMS is sent to them.
Real numbers also work: their code is printed to `journalctl -u
mafia-server`. Switch to `SMS_PROVIDER=eskiz` before real players join.

## App builds against this server

    flutter build ios --release --config-only \
      --dart-define=USE_FAKES=false --dart-define=API_BASE_URL=https://api.<domain>

then build and install with Xcode as usual. A plain build without these
defines uses pretend data.

## Capacity (rough estimate)

With 2 shared cores and about 2.4 GB free, plan on a few matches at once.
Video is the limit: one 12-player match needs roughly 20 to 50 Mbit/s on
the server, and the link is 200 Mbit/s inside Uzbekistan (TAS-IX). If the
game grows, video moves to a second server first.

## Deploys

GitHub Actions builds `server` as a Linux binary (the `server-binary` job
in CI). Deploying will copy it over SSH with a deploy key stored as a
GitHub secret and restart `mafia-server`. Never paste passwords or keys in
chat.
