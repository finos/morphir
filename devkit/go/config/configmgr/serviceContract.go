package configmgr

type ConfigMgr interface {
	LoadHostConfig(workingDir string, workspaceDir *string, hostConfigFilePath *string) error
}
