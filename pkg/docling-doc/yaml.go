package docling

import (
	"gopkg.in/yaml.v3"
)

// ToYAML serializes the document to YAML bytes.
func ToYAML(doc DoclingDocument) ([]byte, error) {
	return yaml.Marshal(doc)
}

// FromYAML deserializes a document from YAML bytes.
func FromYAML(data []byte) (DoclingDocument, error) {
	var doc DoclingDocument
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return DoclingDocument{}, err
	}
	return doc, nil
}
