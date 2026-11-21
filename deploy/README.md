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
   127.0.0.1:8080 only. Memory capped at 512 MB.
4. LiveKit: the official single binary, run by
   `systemd/mafia-livekit.service`, signalling on 127.0.0.1:7880 only.
   Memory capped at 1 GB.
5. nginx: one new file (`nginx/mafia.conf`) for two new hostnames,
   `api.` and `video.`, with certbot certificates.
6. ufw: the only new openings are for video media,
   `ufw allow 7881/tcp` and `ufw allow 50000:50100/udp`.

Undo: `systemctl disable --now mafia-server mafia-livekit`, remove the
nginx file and the two ufw rules, `DROP DATABASE mafia; DROP ROLE mafia;`.

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
