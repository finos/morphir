package main

import "fmt"

type FetchCmd struct{}

func (cmd *FetchCmd) Run(globals *Globals) error {
	fmt.Println("fetching..")
	return nil
}
