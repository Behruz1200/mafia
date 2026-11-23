# Accounts (stream 5)

Sign-up and sign-in, sessions and player profiles. Everything here is stored
only in this server's PostgreSQL (tables in `migrations/0002_accounts_users.sql`).

## How sign-in works

- **Phone:** `POST /v1/auth/phone/start` sends a 6-digit code by SMS (one a
  minute, five an hour per number, valid 5 minutes, 5 tries). `POST
  /v1/auth/phone/verify` checks it and returns an `AuthSession`. The first
  sign-in creates the account. Only numbers from `LAUNCH_COUNTRIES` (today
  `UZ`, `+998`) are accepted; the country comes from the number.
- **Apple:** `POST /v1/auth/apple` with an `AppleSignInRequest`. The server
  checks Apple's signature, our bundle id, expiry and the nonce.
- **Sessions:** access tokens are HS256 JWTs (15 minutes, `sub` = user id).
  Refresh tokens are random, stored hashed, valid 60 days and replaced on
  every `POST /v1/auth/refresh`. Using an old one again signs that device
  chain out (it means the token leaked). `POST /v1/auth/sign-out` ends it.
- **Profile:** `GET/PATCH /v1/me`. Name (2 to 24 characters), language
  (`uz`, `ru`, `en`) and, once, the birth date for the 18+ age gate. The
  date never leaves the server; apps only see `isAdult` and `hasBirthDate`.
- **Deletion:** `DELETE /v1/me` wipes phone, Apple id, name and birth date
  and revokes every session. The user id stays so coin history adds up.

## For other modules

`import 'package:server/auth/auth_guard.dart';`

- `userIdOf(request)`: the caller's user id, or null. Set by
  `authenticate()`, which `lib/src/app.dart` runs for every request.
- `verifyAccessToken(token)`: for the socket's `?token=`.
- `auth.profileOf(userId)` on the `AuthModule` instance in `app.dart`.
- Tests: `issueTestAccessToken(userId, secret)`.

## Settings

| Variable | Needed | What |
| --- | --- | --- |
| `JWT_SECRET` | yes | At least 32 random characters. Changing it signs everyone out. |
| `DATABASE_URL` | yes | `postgres://user:pass@localhost:5432/mafia` |
| `AUTH_STORE` | no | `memory` runs without a database (local only, lost on restart). |
| `SMS_PROVIDER` | no | `console` (default, prints codes to the log) or `eskiz`. |
| `ESKIZ_EMAIL`, `ESKIZ_PASSWORD` | for Eskiz | The Eskiz account login. |
| `ESKIZ_FROM` | no | Sender name approved by Eskiz, default `4546`. |
| `SMS_TEXT` | no | Default `Mafia: tasdiqlash kodi {code}`. Must match the template approved in the Eskiz cabinet. |
| `APPLE_BUNDLE_IDS` | for Apple | The iOS bundle id, comma-separated if several. |
| `AUTH_TEST_PHONES` | no | `+998900000001=123456`: fixed code, no SMS. For App Store review only. |
| `GUEST_SIGN_IN` | no | `true`: `POST /v1/auth/guest` makes a new player with no phone (live tests). Off by default; keep off at launch, every guest gets welcome coins. |
| `GUEST_PER_HOUR` | no | New guests allowed per hour, server-wide (default 30). |
| `LAUNCH_COUNTRIES` | no | Shared with the rest of the server, default `UZ`. |

## Tests

`dart test` runs everything with an in-memory store. To also run against a
real PostgreSQL, point `TEST_DATABASE_URL` at an empty database (its tables
are dropped):

    TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/mafia_test dart test test/auth
