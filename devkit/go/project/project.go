package project

import (
	"encoding/json"
	"github.com/hack-pad/hackpadfs"
	"go.uber.org/zap"
	"io"
)

type Project struct {
	Name              string                    `json:"name"`
	SourceDirectory   string                    `json:"sourceDirectory"`
	ExposedModules    []string                  `json:"exposedModules,omitempty"`
	LocalDependencies []string                  `json:"localDependencies,omitempty"`
	Dependencies      []string                  `json:"dependencies,omitempty"`
	Decorations       map[string]DecorationInfo `json:"decorations,omitempty"`
}

type DecorationInfo struct {
	DisplayName     string `json:"displayName"`
	IR              string `json:"ir"`
	EntryPoint      string `json:"entryPoint"`
	StorageLocation string `json:"storageLocation"`
}

func LoadJsonFile(fs hackpadfs.FS, path string) (*Project, error) {
	file, err := fs.Open(path)
	if err != nil {
		zap.L().Error("Error opening file", zap.Error(err))
		return nil, err
	}
	defer func(file hackpadfs.File) {
		err := file.Close()
		if err != nil {
			zap.L().Error("Error closing file", zap.Error(err))
		}
	}(file)
	p, err := Decode(file)
	if err != nil {
		return nil, err
	}
	return p.init(), nil
}

func Decode(reader io.Reader) (*Project, error) {
	var project Project
	err := json.NewDecoder(reader).Decode(&project)
	if err != nil {
		return nil, err
	}
	return &project, nil
}

func Encode(writer io.Writer, project *Project) error {
	return json.NewEncoder(writer).Encode(project)
}

func (p *Project) init() *Project {
	return p
}
