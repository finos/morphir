package config

type Mode byte

const (
	Global Mode = 1 << iota
	Local
	Upwards
	Unspecified
	UpwardsGlobal = Upwards | Global
	Default       = UpwardsGlobal
)

func NewMode() Mode {
	return Default
}

// IsEmptyOrUnspecified returns true if the Mode is empty or unspecified
func (m *Mode) IsEmptyOrUnspecified() bool {
	return *m == 0 || *m == Unspecified
}

func (m *Mode) HasGlobal() bool {
	return *m&Global == Global
}

func (m *Mode) HasLocal() bool {
	return *m&Local == Local
}

func (m *Mode) HasUpwards() bool {
	return *m&Upwards == Upwards
}

func (m *Mode) HasUpwardsGlobal() bool {
	return *m&UpwardsGlobal == UpwardsGlobal
}

func (m *Mode) HasDefault() bool {
	return *m == Default
}

func (m *Mode) Including(mode Mode) Mode {
	return *m | mode
}

func (m *Mode) IncludingInPlace(mode Mode) {
	*m = m.Including(mode)
}

func (m *Mode) Has(mode Mode) bool {
	return *m&mode == mode
}

func (m *Mode) Canonicalize() Mode {
	if m.IsEmptyOrUnspecified() {
		return Default
	}
	return *m
}

func (m *Mode) ShouldApplyDefaults() bool {
	return m.IsEmptyOrUnspecified()
}
