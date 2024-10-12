package morphircmd

type VerifyCmd struct{}

func (cmd *VerifyCmd) Run(globals *Globals) error {
	println("verifying..")
	return nil
}
