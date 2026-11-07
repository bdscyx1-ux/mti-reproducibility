# Download measurements

Release: https://github.com/bdscyx1-ux/mti-reproducibility/releases/tag/v1.0.0

Download `archives.json`, all required `*.files.csv` indexes and corresponding ZIP parts from the Release assets. Keep them together in a directory named `data-archives` beside the repository. Do not unpack all 57.41 GiB unless needed; the reproduction entry points extract selected files themselves. ZIP parts are independent archives, not pieces of one split ZIP.

If using the GitHub CLI, run from the repository directory:

```powershell
gh release download v1.0.0 --repo bdscyx1-ux/mti-reproducibility --dir ../data-archives --pattern "*.part*.zip" --pattern "*.files.csv" --pattern "archives.json"
python tools/verify_package.py --archives ../data-archives
```

The command downloads the complete archive collection, approximately 3.36 GiB. See QUICKSTART.md to select only supplemental A/B inputs, and HISTORICAL_QUICKSTART.md for the five recoverable historical groups. The archive manifest lists sizes and SHA-256 hashes. `RELEASE_SHA256.csv` also covers non-ZIP assets and convenience packages. Compare hashes after download.

The retained `historical-expanded` archives do not contain the missing AX2 block outcomes. They are surviving control/support records; their presence does not resolve the documented raw-data gap.

## Complete archive inventory

| Archive | Compressed bytes | SHA-256 |
| --- | ---: | --- |
| extra-support.part001.zip | 3622057 | `7aefbc84884ac52f9212f6155b5d17e6a0e5ae638c00f46f261400e323321a58` |
| historical-confirmation.part001.zip | 58883273 | `40633d06cbe6639fda1fa39937adec20649a2c2c1bd47657342755cfb26593f3` |
| historical-confirmation.part002.zip | 39043038 | `20b2a5246dec147ec76c7026ed42c973af7683e522dfdaaa86ece64d09ba6ca0` |
| historical-confirmation.part003.zip | 37934159 | `9f6f418bea8946b5f906b3703bbbbd326d44e8d07d29f3e065953f78197cc1bf` |
| historical-confirmation.part004.zip | 43312343 | `a50012050b860ffa54a55794758e53b1e2cd99b38c2a6b56d503e3196f3f9bb4` |
| historical-confirmation.part005.zip | 35905797 | `30cb2d1f6e1ece20f058cb28127bf909db450a4d05616c96e4f18110ce9afe98` |
| historical-confirmation.part006.zip | 42363424 | `16798c07b635275d5a576e38d5216cff75e2f20f26dea23204c7ea9ffcef9f25` |
| historical-confirmation.part007.zip | 42546510 | `004decd8e49d28c4f93563da1bbcae89a69ee1c13825b94640aa526417f9235c` |
| historical-confirmation.part008.zip | 42057504 | `6ec313fa7cc5a71fbb06650b02b94b87d946b086b5cb21745053bded8a109f5a` |
| historical-confirmation.part009.zip | 4968164 | `3e04cb72d362972f883bc507d58a1cf522b7ba49961649aadb6909e88f4648d4` |
| historical-expanded.part001.zip | 28458069 | `54e5d091884a244613465263f716085858a823530be73121f63afa3d8bf43bda` |
| historical-four-method.part001.zip | 75646365 | `223194da5fe01608269a24c5996924b68e641e94c0d4e0dee750e3024bb67d45` |
| historical-four-method.part002.zip | 55984878 | `0ee804482fb1d1409aeda257cea2a078ad18f2f8517862543628c7a22101f9e0` |
| historical-four-method.part003.zip | 56061759 | `c5c34af037a2eb682e31e15898ab8de4fb6088df7e0062795230d4a7791a4779` |
| historical-four-method.part004.zip | 36714340 | `afff288af2e56615bd7dda4caf4053378cd6de9aa45683919c5f8b034ba60b4a` |
| historical-four-method.part005.zip | 34276557 | `ecd9f56cb07ab1723a0492022abbb5df4a06bcc4ef968aa1795ae9f5d0f37d6d` |
| historical-four-method.part006.zip | 39854036 | `cd1cf04801a4d5fdbdc68d823e8fba00e9569205ec324343dd991eb49dfc8560` |
| historical-four-method.part007.zip | 41704164 | `eb8b470a5dc5f2596535b63c6bc221141b0cc7e2bb382472f442236957838e64` |
| historical-four-method.part008.zip | 40735062 | `cb8b6f895abaefdb1051f900a691f1cd9513bf46d55f86659ea08191cc6e4c03` |
| historical-four-method.part009.zip | 35614893 | `b53dcbc81c84099f39da8cffe199aaa52cff75b0bd0041a3cbbd8542d8f945f5` |
| historical-four-method.part010.zip | 35268852 | `83a300daaca27f7998dd001dd9623bb8489da95d44ba470b6c353d8e66c5436a` |
| historical-four-method.part011.zip | 38926705 | `f654c91ba764a37153f7510f8a71f5f8c13c115d17effdaa90ccc593724c0bb8` |
| historical-four-method.part012.zip | 41442915 | `524c4a7ae478f5de04dc87c63435c0dbd67ea38eeb89f09465e1e44dfef6dd54` |
| historical-four-method.part013.zip | 47892784 | `6b33bac6f67f6ca8d53c350da68e40ef23dc5335019d865875ca78d0102693ef` |
| historical-four-method.part014.zip | 36211317 | `f53f675bde4af4777079085245845c27255135c4245c3077ba1ccf90a627d9f0` |
| historical-four-method.part015.zip | 34286787 | `5c9880ee46307588ad748856259c7b4cc974c60570797e66f8ea427d6f440324` |
| historical-four-method.part016.zip | 38101124 | `e2e9399a0281a316c4f298bd8649c5c37c885a2fe4e0d0a5af162ccc5dbdb3f4` |
| historical-four-method.part017.zip | 39677770 | `f8a13fa017da47b6a49907c8f81a8780809282163fd6f5c0d8bb7d8e4b355eb0` |
| historical-four-method.part018.zip | 43834890 | `bb36689345edf7b1f96f68785f35fbc77ebe014f6ee6d69d912aa8433ed225c2` |
| historical-four-method.part019.zip | 43393239 | `1f64abfd08bfb49a1e4713e8057f75af8acf125866455e39cc42b8ef762b08a5` |
| historical-four-method.part020.zip | 40831672 | `2b2d4e7c586a75c20273c90384c631eb00c86825509bea67a9d94f3fc451d36b` |
| historical-four-method.part021.zip | 41173281 | `e88071003c8052ecc59bb86e226b6d30af926ef59c483d9fcfb968997816bf95` |
| historical-four-method.part022.zip | 42848354 | `6b83622967d68adb0dc5b62f0933c2c9637657125fb0ce5669c47008adf0f4de` |
| historical-four-method.part023.zip | 43590213 | `690e9bbb7ba35f51f88cd424282df45fb9c7a4a821b721835b921297bcac5848` |
| historical-four-method.part024.zip | 43327982 | `7506894505ad2d790b3f342ef4c11195fc2bf61bddda7cf59311d8a6454a9180` |
| historical-four-method.part025.zip | 30553025 | `bb3998c55c74167ba5b70a84c62966d76fd57d74e1912708154f8092f9d7ffa6` |
| historical-movement.part001.zip | 27442968 | `7bd2114b061e78355556c78c5a3a70271c13d48bfb7ea485d6910cfd806e4d1d` |
| historical-mq.part001.zip | 24226697 | `473085bba2ec16ec7409b4fa75d23af4c3f989cb885d2622a2a09233c88b94c8` |
| historical-smsb.part001.zip | 302694329 | `ca3d19ee9d868deabbd7ba2f7f203c8c5cce58e2e04d7d9bc8227e1e0688310a` |
| historical-smsb.part002.zip | 304412945 | `1d44b042f6847109da269786c62992cf9f59804f87539297ff608bf74725b672` |
| historical-smsb.part003.zip | 270571213 | `5647fc1b643128c6b8fcb5a29f38fe31a854e40ad935108eb18aa69edd081c54` |
| historical-smsb.part004.zip | 66505954 | `5332a1769f226579563b10d758ff7da07e6097ea85ddccca74a5c8cd4fd9c969` |
| historical-smsb.part005.zip | 52794304 | `faa63aeff066a26c09dc13050e0a2d6dd687a3f9b322c155fa88a2354f7ce27f` |
| historical-smsb.part006.zip | 52936629 | `4fd682d6ff2bdf7d98f9879c3e3ef04d3584d2df841ba8e26a595a68c24ec8f8` |
| historical-smsb.part007.zip | 50103484 | `9120d8abb30ebff89730eb5f3ebe9a7c6e6a12b787c0a81935ae85fee56cdc2c` |
| historical-smsb.part008.zip | 47886262 | `9ed2fa40823fe52dc36412ade722e8506a34a2e90d446fcd59d496d01e1889f6` |
| historical-smsb.part009.zip | 44926704 | `730f28233f68d485231f55fa013f06a8fc027b0761d2e9dee43f555c5c6765db` |
| historical-smsb.part010.zip | 44957652 | `2fc88e5938212c0d5d009ce07cb3d49f79f14a386f00710ddafab1a505f89766` |
| historical-smsb.part011.zip | 45072215 | `152dac1a25ea47741776b5f01b11d9d86e935f7f4993b94d430e3d9bd193fa4b` |
| historical-smsb.part012.zip | 53831142 | `8af784241dcd696817c48e3f497aac59bf056c7617e381bae7bc760d99e544bc` |
| historical-smsb.part013.zip | 49523144 | `1191f4f12d4a23d16a89c1fe423411ce531a275f3fc55f3bcd2cd7b704d82d70` |
| historical-smsb.part014.zip | 48799899 | `cf9e450e56dc2380c66239286165ca3a5596537d8817976f58632a5668796cef` |
| historical-smsb.part015.zip | 46718655 | `ee607b50ba0825dabb3957d31cce8d7b921ce9ed569e8b3f03f3acdea9bdcbbf` |
| historical-smsb.part016.zip | 46997082 | `d5061996c5c6163049e3d4936dba2b0b5ddbd126b35939cd20933585fccba34b` |
| historical-smsb.part017.zip | 49028306 | `2a5584ded868f8f48789fc104b4aeba225b7623a39a6984b5397cadbd9bee0cf` |
| historical-smsb.part018.zip | 53653942 | `118a5562d8237e71857b1c3b24cc46ce5fa15ccdc0c530d9c2557d1acc0b5b84` |
| historical-smsb.part019.zip | 49898583 | `fbf7e38462cece6cc109d88a020d73567e506dd67aca765703cd00531aa80703` |
| historical-smsb.part020.zip | 48168082 | `f7711e96098e47830e53d8aa4e6b5b85def0ac36f5877a6f09686e504c5b4dfa` |
| historical-smsb.part021.zip | 47263963 | `0c16098013c470a81b4d5a994dc4e73ef2caa5f8b0aecc2acf6add4abebf6663` |
| historical-smsb.part022.zip | 47441734 | `ba9d73c1f1fb46b1aef5b101ca29dfe493d1f7eedcfbb84628733cda19bdcc47` |
| historical-smsb.part023.zip | 20035496 | `a96bf629f1f52e280cbbe8e79fd14ae5fc884a407228da10d6759f7b4a1d571b` |
| smsb-accepted-tables.part001.zip | 151834629 | `e9b092efd807f6b7ba67a43de5feb58af6981d0f9231e773a11ff30cddc18890` |
| supplement-A.part001.zip | 84175701 | `495f15ee1b7ef6158f76b83d9dc5d8e52727fd57498a3f928fe7593d67ac8d01` |
| supplement-A.part002.zip | 16420950 | `eeaabd88f7b14e4cf0ab8a79ba311a01deeb3a4accecfcd3c510c9717285444a` |
| supplement-B.part001.zip | 13124603 | `07813dbe8b50edabff2e056e9d294480131470d97b15cefe16119612bf703394` |
| supplement-inputs.part001.zip | 2416327 | `11d38f19f3f3aa850afaffa7ea13b91b3cdeefebc28f21c7d9a92354803f3211` |
| supplement-plans.part001.zip | 6144761 | `b776a872dfaff9f863e359edc0efda8c400337e0ffa9e0c9deed0ae41cf7fb21` |
