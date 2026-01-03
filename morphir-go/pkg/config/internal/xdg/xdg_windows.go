//go:build windows

package xdg

// configHome returns the Windows config directory.
// Uses %APPDATA% (typically C:\Users\<user>\AppData\Roaming)
func (p *Paths) configHome() string {
	if dir := p.getenv("APPDATA"); dir != "" {
		return dir
	}
	// Fallback: try to construct from home directory
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return home + "\\AppData\\Roaming"
}

// cacheHome returns the Windows cache directory.
// Uses %LOCALAPPDATA% (typically C:\Users\<user>\AppData\Local)
func (p *Paths) cacheHome() string {
	if dir := p.getenv("LOCALAPPDATA"); dir != "" {
		return dir
	}
	// Fallback: try to construct from home directory
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return home + "\\AppData\\Local"
}

// dataHome returns the Windows data directory.
// Uses %LOCALAPPDATA% (typically C:\Users\<user>\AppData\Local)
func (p *Paths) dataHome() string {
	if dir := p.getenv("LOCALAPPDATA"); dir != "" {
		return dir
	}
	// Fallback: try to construct from home directory
	home, err := p.homeDir()
	if err != nil {
		return ""
	}
	return home + "\\AppData\\Local"
}

// systemConfigDir returns the system configuration directory.
// On Windows, this is %PROGRAMDATA% (typically C:\ProgramData)
func (p *Paths) systemConfigDir() string {
	if dir := p.getenv("PROGRAMDATA"); dir != "" {
		return dir
	}
	return "C:\\ProgramData"
}

// isWindows returns true on Windows.
func (p *Paths) isWindows() bool {
	return true
}
