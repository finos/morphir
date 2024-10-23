package task

type MakeProjectRequest struct {
}

type MakeProject struct {
	Meta
	Data MakeProjectRequest
	//Task[MakeProjectRequest]
}

func NewMakeProject() *MakeProject {
	task := &MakeProject{
		Meta: Meta{
			name: "MakeProject",
		},
		Data: MakeProjectRequest{},
	}
	return task
}

func (t *MakeProject) Name() Name {
	return t.name
}
