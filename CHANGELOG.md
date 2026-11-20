# Changelog

## [0.10.1](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.10.0...v0.10.1) (2026-11-20)


### Bug Fixes

* **firmware:** update heapless to 0.9.4 for nine advisories ([#159](https://github.com/guy-with-a-why/telemetry-blackbox/issues/159)) ([5625a3d](https://github.com/guy-with-a-why/telemetry-blackbox/commit/5625a3dc2473d7b6f3ac1174f4d0c98d1c761067))
* **flight:** override fflate to 0.7.5 until satori ships the bump ([#160](https://github.com/guy-with-a-why/telemetry-blackbox/issues/160)) ([0f321c1](https://github.com/guy-with-a-why/telemetry-blackbox/commit/0f321c1c16d065071ff47da4962aec1d08ed5b39))

## [0.10.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.9.0...v0.10.0) (2026-11-19)


### Features

* **deploy:** add ClickHouse's frame tables, deduplicated by Redpanda offset ([#142](https://github.com/guy-with-a-why/telemetry-blackbox/issues/142)) ([d9b4d78](https://github.com/guy-with-a-why/telemetry-blackbox/commit/d9b4d784d6f2bcdaf3a62bf545d8e8b72d42919c)), closes [#15](https://github.com/guy-with-a-why/telemetry-blackbox/issues/15)
* **deploy:** run ClickHouse on data-1 inside Redpanda's free-space floor ([#141](https://github.com/guy-with-a-why/telemetry-blackbox/issues/141)) ([812a2ac](https://github.com/guy-with-a-why/telemetry-blackbox/commit/812a2ac0e03f7caddebb879db6e8ac3d59d15316))

## [0.9.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.8.0...v0.9.0) (2026-11-18)


### Features

* **deploy:** check Redpanda keeps every record across a Pod restart ([#128](https://github.com/guy-with-a-why/telemetry-blackbox/issues/128)) ([2bf3ff4](https://github.com/guy-with-a-why/telemetry-blackbox/commit/2bf3ff4972a3f0ce71572aa2789f79074a129a57)), closes [#14](https://github.com/guy-with-a-why/telemetry-blackbox/issues/14)
* **deploy:** mirror Docker Hub on the host ([#125](https://github.com/guy-with-a-why/telemetry-blackbox/issues/125)) ([61cd2b6](https://github.com/guy-with-a-why/telemetry-blackbox/commit/61cd2b6b645e6a6cfa10727da795f1805900c8ae))
* **deploy:** run Redpanda on a local volume on data-1 ([#127](https://github.com/guy-with-a-why/telemetry-blackbox/issues/127)) ([48cbcd3](https://github.com/guy-with-a-why/telemetry-blackbox/commit/48cbcd3258caed963aee30fc9373b940a5282e85))

## [0.8.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.7.0...v0.8.0) (2026-11-17)


### Features

* **deploy:** snapshot etcd to the host ([#120](https://github.com/guy-with-a-why/telemetry-blackbox/issues/120)) ([e0f7ddb](https://github.com/guy-with-a-why/telemetry-blackbox/commit/e0f7ddb1199ab2a5fa103c21a38a2833e866d01c))

## [0.7.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.6.0...v0.7.0) (2026-11-17)


### Features

* **deploy:** watch the cluster through a control-plane drill ([#111](https://github.com/guy-with-a-why/telemetry-blackbox/issues/111)) ([d0f2cc0](https://github.com/guy-with-a-why/telemetry-blackbox/commit/d0f2cc00dec7079ccac946ed93cbd90bcfb91bdc))

## [0.6.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.5.2...v0.6.0) (2026-11-15)


### Features

* **deploy:** bootstrap the cluster with one command ([#108](https://github.com/guy-with-a-why/telemetry-blackbox/issues/108)) ([2d3929d](https://github.com/guy-with-a-why/telemetry-blackbox/commit/2d3929dda928382d9b3206dcdf503cfa9d507e8a)), closes [#105](https://github.com/guy-with-a-why/telemetry-blackbox/issues/105)

## [0.5.2](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.5.1...v0.5.2) (2026-11-15)


### Bug Fixes

* **deploy:** check every kube-vip and find its interface reliably ([#100](https://github.com/guy-with-a-why/telemetry-blackbox/issues/100)) ([fd73ac9](https://github.com/guy-with-a-why/telemetry-blackbox/commit/fd73ac9ca152f1dd9737f45a6c0efb6c31fdc809))

## [0.5.1](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.5.0...v0.5.1) (2026-11-14)


### Bug Fixes

* **audit:** skip bot pull requests in the blocked-terms scan ([#97](https://github.com/guy-with-a-why/telemetry-blackbox/issues/97)) ([e6e0c27](https://github.com/guy-with-a-why/telemetry-blackbox/commit/e6e0c2712fe67ce6a9e78089a437f4e5039b503a))

## [0.5.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.4.0...v0.5.0) (2026-11-14)


### Features

* **flight:** draw a narrow rack for phones ([#91](https://github.com/guy-with-a-why/telemetry-blackbox/issues/91)) ([bb76d8e](https://github.com/guy-with-a-why/telemetry-blackbox/commit/bb76d8e5f79691af36288c6869af2b86b7e7dc55)), closes [#90](https://github.com/guy-with-a-why/telemetry-blackbox/issues/90)
* **flight:** draw the progress strips as a rack with Satori and React ([#88](https://github.com/guy-with-a-why/telemetry-blackbox/issues/88)) ([4e6f1ac](https://github.com/guy-with-a-why/telemetry-blackbox/commit/4e6f1aca4c7c88169fb667e4b9be97775410f14f)), closes [#86](https://github.com/guy-with-a-why/telemetry-blackbox/issues/86)

## [0.4.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.3.0...v0.4.0) (2026-11-14)


### Features

* **deploy:** configure and check the HA control plane ([#84](https://github.com/guy-with-a-why/telemetry-blackbox/issues/84)) ([a12045c](https://github.com/guy-with-a-why/telemetry-blackbox/commit/a12045c67ee09c09dea819b97adc4476724456dd))
* **deploy:** mirror quay.io and ghcr.io on the host ([#83](https://github.com/guy-with-a-why/telemetry-blackbox/issues/83)) ([da2937f](https://github.com/guy-with-a-why/telemetry-blackbox/commit/da2937f637bcd6a944ee8490b50a6f41a10c0ed1)), closes [#82](https://github.com/guy-with-a-why/telemetry-blackbox/issues/82)

## [0.3.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.2.0...v0.3.0) (2026-11-14)


### Features

* **deploy:** build the five cluster VMs with cloud-init and a local registry ([#74](https://github.com/guy-with-a-why/telemetry-blackbox/issues/74)) ([49fce66](https://github.com/guy-with-a-why/telemetry-blackbox/commit/49fce66bc1a2f60935918cedc9a9044e8fb51995)), closes [#10](https://github.com/guy-with-a-why/telemetry-blackbox/issues/10)
* **deploy:** cache packages and control-plane images on the host ([#78](https://github.com/guy-with-a-why/telemetry-blackbox/issues/78)) ([a224770](https://github.com/guy-with-a-why/telemetry-blackbox/commit/a22477074ad10cb8d109ab8a0ae695b5a9778ba3)), closes [#75](https://github.com/guy-with-a-why/telemetry-blackbox/issues/75)
* **release:** attach build provenance to the firmware ([#77](https://github.com/guy-with-a-why/telemetry-blackbox/issues/77)) ([d5b9951](https://github.com/guy-with-a-why/telemetry-blackbox/commit/d5b9951e93f63242808c363df3137c81848700c2))

## [0.2.0](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.1.2...v0.2.0) (2026-11-14)


### Features

* **firmware:** boot Embassy firmware on an STM32F4 in Renode ([#69](https://github.com/guy-with-a-why/telemetry-blackbox/issues/69)) ([ac59e97](https://github.com/guy-with-a-why/telemetry-blackbox/commit/ac59e97f24c8673b69020bb080106e403773d591)), closes [#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3)

## [0.1.2](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.1.1...v0.1.2) (2026-11-14)


### Bug Fixes

* **audit:** drop the trailer exemptions from the commit scan ([#63](https://github.com/guy-with-a-why/telemetry-blackbox/issues/63)) ([30c970e](https://github.com/guy-with-a-why/telemetry-blackbox/commit/30c970ea817c09bfad92c20906b6ce08b7defd98))

## [0.1.1](https://github.com/guy-with-a-why/telemetry-blackbox/compare/v0.1.0...v0.1.1) (2026-11-13)


### Bug Fixes

* **audit:** let the release bot's trailer through the commit scan ([#54](https://github.com/guy-with-a-why/telemetry-blackbox/issues/54)) ([be5f732](https://github.com/guy-with-a-why/telemetry-blackbox/commit/be5f732943eb60e60aa379eb0dbb4acd790623e4))

## 0.1.0 (2026-11-13)


### Features

* track progress with a flight strip ([a3bef6b](https://github.com/guy-with-a-why/telemetry-blackbox/commit/a3bef6bafc1e6b71c02cdeee404e32f42a7a2025))


### Bug Fixes

* **brand:** keep the dark wordmark legible on light pages ([ffce752](https://github.com/guy-with-a-why/telemetry-blackbox/commit/ffce752154a753b8e8ebc9bdc0f5d1e9392c2c47))
* **flight:** keep issue text intact when joining the pages ([#43](https://github.com/guy-with-a-why/telemetry-blackbox/issues/43)) ([67132f2](https://github.com/guy-with-a-why/telemetry-blackbox/commit/67132f27550d62089c558e32d1c93c680e7033f8))
* **flight:** take off when the tracker launched ([c5fac1f](https://github.com/guy-with-a-why/telemetry-blackbox/commit/c5fac1f50d39ed1350ddd8d69b1b8ad79c2ba6a3))
