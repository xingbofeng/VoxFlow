# Rime Native Frameworks

These xcframeworks are the Hamster-compatible native Rime dependency bundle for
the Mashangxie iOS Chinese input target.

- Source: `https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz`
- Downloaded: 2026-07-06
- Reason: Hamster commit `65693706d01fc6c19ed6071968e542b0a2ef3f36` expects the
  same framework names from `Frameworks.tgz`, but its hardcoded
  `https://github.com/imfuxiao/LibrimeKit/releases/download/2.4.2/Frameworks.tgz`
  URL currently returns HTTP 404.
- Scope: copied as native vendor dependencies for the RimeKit-backed
  `NativeChineseRimeBridge`; `RimeKitObjC` owns the copied ObjC/C wrapper and
  native links, while the keyboard path injects the Swift bridge through
  `ChineseInputSession` without changing the Dictus UI shell.

Expected xcframeworks:

- `boost_atomic.xcframework`
- `boost_filesystem.xcframework`
- `boost_regex.xcframework`
- `boost_system.xcframework`
- `libglog.xcframework`
- `libleveldb.xcframework`
- `libmarisa.xcframework`
- `libopencc.xcframework`
- `librime.xcframework`
- `libyaml-cpp.xcframework`

Validation notes:

- `ChineseInputTests.testRimeNativeVendorFrameworksArePresentForIOSDevice`
  verifies that every expected xcframework exists and contains an iOS arm64
  device slice.
- These artifacts are enough for the dedicated `RimeNativeLinkProbe` iOS device
  link check, the `RimeNativeRuntimeTests` x86_64 simulator runtime check, and
  the `NativeChineseRimeBridge` path linked by `MashangxieKeyboard`.
  They are still not enough to mark Phase 2 complete without physical-device
  host-field validation. Some xcframeworks only provide x86_64 simulator slices,
  so arm64 simulator linkage remains intentionally unsupported for this fallback
  bundle.
- This fallback bundle does not export the newer `RimeReplaceInput` symbol used
  by the copied Hamster ObjC bridge. `ChineseInput/NativeProbe/RimeCompatibilityShim.c`
  provides a link-probe fallback that returns `False`; production Rime behavior
  must account for that limitation or pin a newer compatible LibrimeKit bundle.
