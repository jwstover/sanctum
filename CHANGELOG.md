# [1.1.0](https://github.com/jwstover/sanctum/compare/v1.0.0...v1.1.0) (2026-07-13)


### Features

* **decks:** sync decks from MarvelCDB and make decks first-class ([9c7de0b](https://github.com/jwstover/sanctum/commit/9c7de0b1dc8d7087bb62a2dac414ec0f5ae98d2d))



# [1.0.0](https://github.com/jwstover/sanctum/compare/v0.13.0...v1.0.0) (2026-07-13)


### Bug Fixes

* **ci:** retry migrations on cold Neon compute and fix changelog PR quoting ([038bd21](https://github.com/jwstover/sanctum/commit/038bd21baa2ccd53febc77532adabef748f632a2))
* **ci:** serialize changelog job to prevent version tag races ([0f8a9e6](https://github.com/jwstover/sanctum/commit/0f8a9e61c354758cd2560b6cbf34fc0a0f1a5503))
* **oban:** migrate Oban schema to v14 for 2.23 ([3485554](https://github.com/jwstover/sanctum/commit/3485554248b968f5eb43ec2b68be6e4e2faf9319))


### chore

* **deps:** upgrade constraint-blocked majors ([7c9b2c0](https://github.com/jwstover/sanctum/commit/7c9b2c0c35c6ea869f3112e8605a161ff2f91622))


### Features

* **auth:** lock /cards/* admin pages behind an admin flag ([c66fd85](https://github.com/jwstover/sanctum/commit/c66fd85c42280adff6f884e9bfc9170fc0159deb))
* **cards:** admin LiveView to trigger and watch card syncs ([3fd2c6d](https://github.com/jwstover/sanctum/commit/3fd2c6d7b470507505bfcae9a73ef99897813491))
* **cards:** paginate /cards listing with infinite scroll ([4dfa9db](https://github.com/jwstover/sanctum/commit/4dfa9db1d3b64091d84d97293c8f696a0f8abee4))
* **cards:** sync catalog from MarvelCDB with images mirrored to Tigris ([0ca5998](https://github.com/jwstover/sanctum/commit/0ca59985bb54a2943fc1e238e977ee55881394ef))


### BREAKING CHANGES

* **deps:** handled: phoenix_live_view 1.2 validates component
global attributes, so `<.button type=...>` required adding `type` to the
button component's :global include list. Its updated HEEx formatter also
reflowed whitespace in a few templates (cosmetic).

Green under Elixir 1.18.4/OTP28: compile --warnings-as-errors, format,
credo, sobelow, deps.unlock --check-unused, 107 tests.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>



# [0.13.0](https://github.com/jwstover/sanctum/compare/v0.12.0...v0.13.0) (2026-07-13)


### Features

* **auth:** add UserIdentity for OAuth (ash_authentication 4.14) ([1fb7550](https://github.com/jwstover/sanctum/commit/1fb75502020a3376c694aaf01d66a413f81a1a91))



# [0.12.0](https://github.com/jwstover/sanctum/compare/v0.11.0...v0.12.0) (2026-07-12)



## [0.10.3](https://github.com/jwstover/sanctum/compare/v0.10.2...v0.10.3) (2026-07-10)


### Features

* add required game_id to GameCard ([f0f6078](https://github.com/jwstover/sanctum/commit/f0f60785e5a9ab3ac9f7f66366afbee6ed9a225f))



# [0.11.0](https://github.com/jwstover/sanctum/compare/v0.10.3...v0.11.0) (2026-07-10)


### Features

* add cascade deletes, game_cards indexes, and game destroy ([9dc55d5](https://github.com/jwstover/sanctum/commit/9dc55d5fcd3072d41091a89a498d1a1d22597bbc))



