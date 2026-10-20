import {mkdirSync} from 'node:fs';
import {delimiter, dirname, join, resolve} from 'node:path';

/**
 * Application acceptance owns these directories, including global configuration
 * and tool registries. Ambient Morphir settings, caches and Node preload hooks
 * must not make a built or installed CLI pass. Declare fixture/tool exceptions
 * at the call site instead of copying the invoking developer's environment.
 */
export function headlessEnvironment(root: string, bindings: NodeJS.ProcessEnv = {}): NodeJS.ProcessEnv {
  const base = resolve(root);
  const directories = Object.fromEntries(['home', 'config', 'cache', 'data', 'state', 'runtime', 'system', 'morphir', 'tmp']
    .map(name => [name, join(base, name)]));
  for (const path of Object.values(directories)) mkdirSync(path, {recursive: true, mode: 0o700});
  // The selected Node executable and standard OS tools are sufficient for these
  // fixture hosts. Compiler/SDK paths, when needed, are explicit bindings.
  const windowsRoot = process.env.SystemRoot ?? process.env.SYSTEMROOT ?? 'C:\\Windows';
  const systemPaths = process.platform === 'win32'
    ? [join(windowsRoot, 'System32'), windowsRoot, join(windowsRoot, 'System32', 'Wbem')]
    : ['/usr/bin', '/bin', '/usr/sbin', '/sbin'];
  return {
    PATH: [dirname(process.execPath), ...systemPaths].join(delimiter),
    ...(process.platform === 'win32' ? {SystemRoot: windowsRoot, WINDIR: windowsRoot,
      ComSpec: join(windowsRoot, 'System32', 'cmd.exe'), PATHEXT: '.COM;.EXE;.BAT;.CMD'} : {}),
    HOME: directories.home, USERPROFILE: directories.home,
    APPDATA: directories.config, LOCALAPPDATA: directories.data, PROGRAMDATA: directories.system,
    XDG_CONFIG_HOME: directories.config, XDG_CACHE_HOME: directories.cache,
    XDG_DATA_HOME: directories.data, XDG_STATE_HOME: directories.state, XDG_RUNTIME_DIR: directories.runtime,
    MORPHIR_HOME: directories.morphir,
    TMPDIR: directories.tmp, TMP: directories.tmp, TEMP: directories.tmp,
    DISPLAY: '', WAYLAND_DISPLAY: '', XAUTHORITY: '', DBUS_SESSION_BUS_ADDRESS: '',
    ...bindings,
  };
}
