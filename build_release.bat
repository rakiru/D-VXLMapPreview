del d-vxlmappreview.exe
dub build --force --build=release --arch=x86
move /Y d-vxlmappreview.exe bin/d-vxlmappreview_x86.exe
dub build --force --build=release --arch=x86_64
move /Y d-vxlmappreview.exe bin/d-vxlmappreview_x64.exe
