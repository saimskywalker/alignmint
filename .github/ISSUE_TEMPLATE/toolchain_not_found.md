---
name: Toolchain not found (exit 2)
about: The check exits 2 on a machine where the tools really are installed
labels: toolchain
---

Exit 2 means the check could not verify the artifact — usually correctly. Open
this if the tool it is asking for **is** installed and it still cannot find it,
which is a detection bug worth fixing.

**The message it printed**

```
```

**Where the tool actually lives**

```
$ command -v llvm-objdump; command -v bundletool; command -v zipalign
$ ls "$ANDROID_HOME"/ndk 2>/dev/null
$ ls "$ANDROID_HOME"/build-tools 2>/dev/null
```

**Relevant environment**

```
$ echo "ANDROID_HOME=$ANDROID_HOME"
$ echo "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
$ echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
$ echo "ANDROID_NDK_ROOT=$ANDROID_NDK_ROOT"
```

**How the SDK was installed**

- [ ] Android Studio
- [ ] `sdkmanager` command line tools
- [ ] Homebrew / a distribution package
- [ ] A CI image (which one:              )
- [ ] Something else:

**Does `--ndk` work as a workaround?**

<!-- `android-16kb-check --ndk /path/to/ndk/<version> <artifact>` — if that
     succeeds, the bug is in auto-detection, which narrows it a lot. -->

**Did you use an AI tool to write this issue?**

<!-- See "AI-assisted contributions" in CONTRIBUTING.md. -->

- [ ] No
- [ ] Yes, for parts (tool and model: ...)
- [ ] Yes, mostly (tool and model: ...)
- [ ] I wrote this issue in my own words.
