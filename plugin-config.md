The deken-plugin for Pd can be configured via a simple text-file.

# deken-plugin.conf

The configuration file for the deken-plugin
is called `deken-plugin.conf`.

Put it either directly near the `deken-plugin.tcl` file,
or into a system-specific place (`$PdPath` resp `%PdPath%` are the installation directory of your Pd, `~` is your home directory):

### Linux
- `$PdPath/extra/deken-plugin/deken-plugin.conf`
- `/usr/local/lib/pd-externals/deken-plugin/deken-plugin.conf`
- `~/pd-externals/deken-plugin/deken-plugin.conf`

### OSX
- `$PdPath/extra/deken-plugin/deken-plugin.conf`
- `/Library/Pd/deken-plugin/deken-plugin.conf`
- `~/Library/Pd/deken-plugin/deken-plugin.conf`

### W32
- `%PdPath%\extra\deken-plugin\deken-plugin.conf`
- `%AppData%\Pd\deken-plugin\deken-plugin.conf`
- `%CommonProgramFiles%\Pd\deken-plugin\deken-plugin.conf`

## Configuration Values

Here are the possible values:

 * `installpath` = Path where you would want to install the externals
 (default: the first writable path in the standard search paths)
 (note: you should *always* use `/` as path-separator, even on W32!)


All values are optional.

## Example

```
installpath /tmp/dekentest
## On W32 we would use something like
#installpath D:/Pd/deken-test
```
