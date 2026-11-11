module Acme.Demo.Pricing

type Car = { plate : string; seats : int }

let seats (car : Car) : int = (car).seats
