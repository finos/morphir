package configmode

type ConfigMode byte

const (
	Global ConfigMode = 1 << iota
	Local
	Upwards
	Unspecified
	UpwardsGlobal = Upwards | Global
	Default       = UpwardsGlobal
)

// IsEmptyOrUnspecified returns true if the ConfigMode is empty or unspecified
func (c *ConfigMode) IsEmptyOrUnspecified() bool {
	return *c == 0 || *c == Unspecified
}

func (c *ConfigMode) HasGlobal() bool {
	return *c&Global == Global
}

func (c *ConfigMode) HasLocal() bool {
	return *c&Local == Local
}

func (c *ConfigMode) HasUpwards() bool {
	return *c&Upwards == Upwards
}

func (c *ConfigMode) HasUpwardsGlobal() bool {
	return *c&UpwardsGlobal == UpwardsGlobal
}

func (c *ConfigMode) HasDefault() bool {
	return *c == Default
}

func (c *ConfigMode) Including(mode ConfigMode) ConfigMode {
	return *c | mode
}

func (c *ConfigMode) IncludingInPlace(mode ConfigMode) {
	*c = c.Including(mode)
}

func (c *ConfigMode) Has(mode ConfigMode) bool {
	return *c&mode == mode
}

func (c *ConfigMode) Canonicalize() ConfigMode {
	if c.IsEmptyOrUnspecified() {
		return Default
	}
	return *c
}
