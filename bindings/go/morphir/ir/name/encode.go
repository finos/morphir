package name

import (
	"encoding/json"
)

func (n Name) MarshalJSON() ([]byte, error) {
	return json.Marshal(n.ToList())
}
