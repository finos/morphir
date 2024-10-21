package morphircmd

import (
	"go.uber.org/zap"
)

type VerifyCmd struct{}

func (cmd *VerifyCmd) Run(globals *Globals, logger zap.Logger) error {
	sugar := logger.Sugar()
	sugar.Info("Performing verification ...")
	sugar.Infow("Working directory", "path", globals.WorkingDir)
	println("verifying..")
	return nil
}
