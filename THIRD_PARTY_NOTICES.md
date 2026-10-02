# Third-party software

BLAKE2b Miner is MIT licensed. The app bundle also contains the DATUM Gateway
(`Contents/MacOS/datum_gateway`), built by `scripts/build-datum-gateway.sh`
from the pinned sources below and statically linked with its libraries. Every
source is publicly available at the URLs given, and the script rebuilds
the gateway exactly, which also lets you relink it against modified versions
of the LGPL libraries.

| Component | Version | License | Source |
| --- | --- | --- | --- |
| DATUM Gateway (CONVOY) | commit ac9b70c8 | MIT | https://github.com/CONVOYMining/datum_gateway |
| libsodium | 1.0.22 | ISC | https://libsodium.org |
| Jansson | 2.15.1 | MIT | https://github.com/akheron/jansson |
| GNU libmicrohttpd | 1.0.10 | LGPL-2.1-or-later | https://www.gnu.org/software/libmicrohttpd/ |
| argp-standalone | 1.5.0 | LGPL-2.1-or-later | https://github.com/argp-standalone/argp-standalone |
| epoll-shim | 0.0.20240608 | MIT | https://github.com/jiixyj/epoll-shim |
| libcurl | system (macOS) | curl license | https://curl.se |

The header-v2 test vectors in `Sources/MinerCore/TestVectors.swift` come from
Bitcoin Knots (MIT), https://github.com/bitcoinknots/bitcoin.
