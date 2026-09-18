# [1.86.0](https://github.com/jwstover/sanctum/compare/v1.85.0...v1.86.0) (2026-09-18)


### Features

* **tts:** bag-name resolution layer for Hitch's TTS mod ([711a4e8](https://github.com/jwstover/sanctum/commit/711a4e8f9539bbdcb4982bb9c2a7d4bbb2d56f2d))



# [1.85.0](https://github.com/jwstover/sanctum/compare/v1.84.0...v1.85.0) (2026-09-16)


### Features

* **decks:** built-in hero side decks on both deck surfaces ([c80065b](https://github.com/jwstover/sanctum/commit/c80065be25dbb891934d090f00db34946b96bf4e))



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



