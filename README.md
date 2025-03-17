# DNS Switcher
Quickly change your DNS settings in macOS (by Matt McNeeney).

[View original documentation](http://mattmcneeney.github.io/DNSSwitcher/)

# Installation
- Uncompress the file [DNSSwitcher.zip](DNSSwitcher.zip) and copy ```DNSSwitcher.app``` to ```Applications``` folder.
- Run in a terminal ```xattr -dr com.apple.quarantine "/Applications/DNSSwitcher.app"``` to allow unidentified app.
- Add ```DNSSwitcher.app``` to ```Open at Login``` (System Settings -> General ->  Login Items & Extensions -> Open at Login) to run automatically.

# Changelog
## Version 1.1.0
- Compatibility with Swift 5
- Adjustments for Xcode 11.5
- Skip success message after DNS change
- Hide menu item "About"
## Version 1.1.5
- Minor changes to be more compatible with latest Xcode and macOS
