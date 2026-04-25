rm -rf Dynamic.AppDir
mkdir Dynamic.AppDir
cp -r build/linux/x64/release/bundle/* Dynamic.AppDir
cp -r buildtools/appimage_config/* Dynamic.AppDir
cp assets/icons/icon-padded.png Dynamic.AppDir
sudo chmod +x buildtools/appimagetool-x86_64.AppImage
sudo chmod +x Dynamic.AppDir/AppRun
./buildtools/appimagetool-x86_64.AppImage Dynamic.AppDir
