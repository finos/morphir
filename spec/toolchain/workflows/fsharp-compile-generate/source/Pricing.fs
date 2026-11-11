namespace Acme.Demo
module Pricing =
    type Car = { Plate: string; Seats: int }
    let seats (car: Car) : int = car.Seats