package configmode

type ConfigMode byte

const (
	Global ConfigMode = 1 << iota
	Local
	Upwards
	UpwardsGlobal = Upwards | Global
	Default       = UpwardsGlobal
)

func (c *ConfigMode) IsGlobal() bool {
	return *c&Global == Global
}

func (c *ConfigMode) IsLocal() bool {
	return *c&Local == Local
}

func (c *ConfigMode) IsUpwards() bool {
	return *c&Upwards == Upwards
}

func (c *ConfigMode) IsUpwardsGlobal() bool {
	return *c&UpwardsGlobal == UpwardsGlobal
}

func (c *ConfigMode) IsDefault() bool {
	return *c == Default
}

func (c *ConfigMode) Including(mode ConfigMode) ConfigMode {
	return *c | mode
}

func (c *ConfigMode) IncludingInPlace(mode ConfigMode) {
	*c = c.Including(mode)
}

func (c *ConfigMode) Matches(mode ConfigMode) bool {
	return *c&mode == mode
}
