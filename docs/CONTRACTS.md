# Changing the contracts

`packages/contracts` is the agreement between all streams: models, the HTTP
routes and socket messages, and the interfaces each stream implements. It is
frozen once the foundation merges, so the six streams can work in parallel.

To change it:

1. Open a small PR that changes only `packages/contracts` (plus fakes and
   tests in the same package). Title it `contracts: ...`.
2. Say which streams are affected. Prefer adding fields with defaults over
   renaming or removing, so nobody breaks.
3. Enum values are stored by name: add new values at the end, never rename.
4. The foundation owner reviews it (CODEOWNERS). Merge it before the
   feature PR that needs it.

Rules the contracts encode, which do not change without a product decision:

- The server decides everything: roles, votes, results, coins. The app only
  shows state and sends actions.
- Coins are bought and won or lost in matches, but never leave the app: no
  cash-out, no transfers between players (decided 2026-11-21).
- A player's role is only ever sent on that player's own socket.
- Personal data (profiles) is stored only on our server in Uzbekistan.
