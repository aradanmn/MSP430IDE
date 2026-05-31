# App Icon

The app icon is generated programmatically (CoreGraphics, no Xcode/asset
catalog required) by `render.swift`. Concept **C**: TI-LaunchPad red
background, white line-art microcontroller, glowing green LED.

## Regenerate `Resources/AppIcon.icns`

```sh
cd Design/icon
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
emit() { swift render.swift emit c "$1" "AppIcon.iconset/$2"; }
emit 16  icon_16x16.png       ; emit 32   icon_16x16@2x.png
emit 32  icon_32x32.png       ; emit 64   icon_32x32@2x.png
emit 128 icon_128x128.png     ; emit 256  icon_128x128@2x.png
emit 256 icon_256x256.png     ; emit 512  icon_256x256@2x.png
emit 512 icon_512x512.png     ; emit 1024 icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o ../../Resources/AppIcon.icns
```

`render.swift preview <dir>` renders all three concepts (a/b/c) at 512px
for comparison. The Makefile copies `Resources/AppIcon.icns` into the
`.app` bundle and `Info.plist` points at it via `CFBundleIconFile`.
