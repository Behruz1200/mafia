# Video (stream 3)

Mints LiveKit tokens and keeps LiveKit in step with the game.

## Rules (`call_policy.dart`)

| Phase | Table call | Mafia call |
| --- | --- | --- |
| No match, lobby, role reveal, ended | everyone talks | closed |
| Night | everyone connected, **nobody** talks | alive Mafia and Don talk |
| Day, voting | alive players talk, the dead watch | closed |

Everyone stays in the table room all night, so the town cannot see who
left for the Mafia call.

## Wiring it in

- **Auth (stream 5)** puts the user id in `request.context['userId']`.
- **Rooms (stream 2)** implements `CallRoomDirectory` and passes it in:
  `CallModule(directory: myRooms)` in `lib/src/app.dart`. Until then
  `POST /v1/rooms/<id>/call` answers 501.
- After every phase change or death, the match loop calls
  `callService.syncPhase(next, previous: prev)`. This mutes or unmutes
  players live; a token alone is only checked when someone connects.
  Optionally push `callService.grantsFor(next)` to each player's own
  socket as `CallGrantIssued` (a Mafia grant only goes to that Mafia player).
- When a room closes: `callService.closeRoom(roomId, lastMatchId: ...)`.

## Settings

`LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` as in the server
env. Optional `LIVEKIT_API_URL` (e.g. `http://127.0.0.1:7880`) so room
admin calls stay on the machine; defaults to `LIVEKIT_URL` over https.

Video quality is set in the app (`CallQuality`): 320x240 at 15 fps,
about 140 kbit/s, one layer, plus 24 kbit/s speech with silence
suppression. A 12-player day uses roughly 20 Mbit/s on the server.
