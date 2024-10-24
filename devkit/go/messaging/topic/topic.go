package topic

import "strings"

// Topic represents a messaging topic.
type Topic []string

func FromString(topic string) Topic {
	parts := strings.Split(topic, ".")
	return parts
}
