package configloader

// This file previously contained conversion functions that imported the config package.
// Those functions have been moved to the config package itself to avoid import cycles.
// The internal loader now returns raw map[string]any, and the public config package
// handles conversion to the Config struct using config.FromMap().
