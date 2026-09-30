# [1.92.0](https://github.com/jwstover/sanctum/compare/v1.91.1...v1.92.0) (2026-09-30)


### Features

* **marvelcdb:** add OAuth2 account linking ([e2746d5](https://github.com/jwstover/sanctum/commit/e2746d584f2c829c351062f365b12a2eb94b380b))



## [1.91.1](https://github.com/jwstover/sanctum/compare/v1.91.0...v1.91.1) (2026-09-30)


### Bug Fixes

* **deps:** prepare for ash 3.33 / ash_authentication 4.15 ([0f0762d](https://github.com/jwstover/sanctum/commit/0f0762d163023ace3998dd657550e6c9ff7e612b)), closes [#399](https://github.com/jwstover/sanctum/issues/399)



# [1.91.0](https://github.com/jwstover/sanctum/compare/v1.90.0...v1.91.0) (2026-09-30)


### Bug Fixes

* **decks:** let likes_max_pages: 0 disable the MCDB likes walk ([ba94bb4](https://github.com/jwstover/sanctum/commit/ba94bb446ea01547d9a0bb986e7572329eb545fa))


### Features

* **decks:** adaptive per-decklist MCDB like-count refresh scheduler ([6e934c3](https://github.com/jwstover/sanctum/commit/6e934c3eede0b2a9f5039031e786be563772bf39))
* **decks:** daily MarvelCDB social refresh cron (top liked + newest pages) ([e4c2c14](https://github.com/jwstover/sanctum/commit/e4c2c141ea22127e65a48054e77e85b77709c702)), closes [#74](https://github.com/jwstover/sanctum/issues/74) [#74](https://github.com/jwstover/sanctum/issues/74) [#74](https://github.com/jwstover/sanctum/issues/74)



# [1.90.0](https://github.com/jwstover/sanctum/compare/v1.89.0...v1.90.0) (2026-09-25)


### Bug Fixes

* **decks:** drop unused default arg from mcdb scrape test helper ([fb762da](https://github.com/jwstover/sanctum/commit/fb762da6fd3abe690226e6c57eed6fd7dff1665a))


### Features

* **decks:** paced MarvelCDB list-page sweep for usernames and like counts ([20816ea](https://github.com/jwstover/sanctum/commit/20816ea2d3f5411fdaf210d5ab466dc7293a2405))



# [1.89.0](https://github.com/jwstover/sanctum/compare/v1.88.0...v1.89.0) (2026-09-25)


### Bug Fixes

* **decks:** drop MarvelCDB profile links, keep numeric fallback label ([364cd68](https://github.com/jwstover/sanctum/commit/364cd68e1992eae78f60490a0388c27c9de3e190))


### Features

* **decks:** credit MarvelCDB authors on deck tiles and deck page ([31440e8](https://github.com/jwstover/sanctum/commit/31440e8d1c840dfcf4256ea6ac5bed2f552e514e))
* **search:** add author: deck search field ([3419030](https://github.com/jwstover/sanctum/commit/3419030559c80bb13ada1be0bfb783d0571ccf4b))



