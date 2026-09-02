# [1.84.0](https://github.com/jwstover/sanctum/compare/v1.83.0...v1.84.0) (2026-09-02)


### Bug Fixes

* **decks:** stack the hand simulator below the decklist on mobile ([6c72970](https://github.com/jwstover/sanctum/commit/6c72970ba07523a6c3f1a77f4c5c4b7af1e45c83))
* **decks:** trim the mulligan hint copy ([d836d15](https://github.com/jwstover/sanctum/commit/d836d1531aea60a5c0eb94827886ba98d55f4674))


### Features

* **decks:** add opening-hand draw simulator to deck view ([74481b8](https://github.com/jwstover/sanctum/commit/74481b82baf9cef1d4b90292fb57dba2580ff888))



# [1.83.0](https://github.com/jwstover/sanctum/compare/v1.82.0...v1.83.0) (2026-08-18)


### Features

* **cards:** add CardSide.aspect_def FK to Aspect (phase 2a) ([b5c1239](https://github.com/jwstover/sanctum/commit/b5c1239b73734cf00513b755c8150699a4210a5b))



# [1.82.0](https://github.com/jwstover/sanctum/compare/v1.81.0...v1.82.0) (2026-08-12)


### Bug Fixes

* **config:** require real CLOAK_KEY in prod_local, not the dev key ([3bdd056](https://github.com/jwstover/sanctum/commit/3bdd05645f22afe46acec2bed9b900a33dcc3767))


### Features

* **accounts:** encrypted UserApiKey resource for BYOK vision extraction ([12efc69](https://github.com/jwstover/sanctum/commit/12efc69ecb26e9a6b465fed86e36746cfe55bef8))
* **homebrew:** power Fill from image with the user's own key (BYOK) ([b36bc91](https://github.com/jwstover/sanctum/commit/b36bc91a52cecc4404dc50bc485687537b059a88))
* **profile:** BYOK Anthropic key management on the profile page ([7acec3b](https://github.com/jwstover/sanctum/commit/7acec3bbcce53785b564b5b64fc4baebf6264136))
* **profile:** let users upload their own profile picture ([73cc572](https://github.com/jwstover/sanctum/commit/73cc572c856e3f02125da9515d850e2cd9f7410a))
* **vision:** add CardVision.validate_key/1 for BYOK key validation ([ebd1b3d](https://github.com/jwstover/sanctum/commit/ebd1b3d17d9df9c6c68ea4fdc3db8071f21f804a))



# [1.81.0](https://github.com/jwstover/sanctum/compare/v1.80.0...v1.81.0) (2026-07-30)


### Features

* **decks:** MarvelCDB-style deck charts on both deck surfaces ([2b4de77](https://github.com/jwstover/sanctum/commit/2b4de77c31814afe22b41803aa7e79058318ab75))



# [1.80.0](https://github.com/jwstover/sanctum/compare/v1.79.0...v1.80.0) (2026-07-30)


### Bug Fixes

* **vision:** sniff image magic bytes for data-URL media type ([df37f0c](https://github.com/jwstover/sanctum/commit/df37f0cb5eab3dfa2fd93f61ce06e8c16f3f5ad4))


### Features

* **vision:** pluggable providers + model eval harness for card extraction ([dd142ab](https://github.com/jwstover/sanctum/commit/dd142ab9d97769fc4e1777a728c9e6039d8ee644))
* **vision:** record token usage in eval reports ([1e2aac6](https://github.com/jwstover/sanctum/commit/1e2aac68cc3d806be879c555ca7f3a15f7dbdcaa))
* **vision:** switch extraction default to claude-sonnet-5 ([604243d](https://github.com/jwstover/sanctum/commit/604243d44bbf12dfe570ddf9c614b78d4c9170cc))



