package vfs

// WriteOp identifies the type of write operation being performed.
type WriteOp string

const (
	OpCreateFile   WriteOp = "create_file"
	OpCreateFolder WriteOp = "create_folder"
	OpUpdateFile   WriteOp = "update_file"
	OpDelete       WriteOp = "delete"
	OpMove         WriteOp = "move"
)

// WriteRequest contains information about a pending write operation.
type WriteRequest struct {
	Op      WriteOp
	Path    VPath
	MoveTo  *VPath // Only set for move operations
	Mount   string
	Options WriteOptions
}

// PolicyDecision represents the result of a policy check.
type PolicyDecision int

const (
	// PolicyAllow permits the write operation.
	PolicyAllow PolicyDecision = iota
	// PolicyDeny rejects the write operation.
	PolicyDeny
	// PolicySkip defers to the next policy in the chain.
	PolicySkip
)

// PolicyResult contains the outcome of a policy evaluation.
type PolicyResult struct {
	Decision PolicyDecision
	Reason   string // Human-readable explanation for deny decisions
}

// WritePolicy evaluates write requests and returns allow/deny decisions.
// Policies can be chained together, with PolicySkip deferring to the next policy.
type WritePolicy interface {
	Evaluate(req WriteRequest) PolicyResult
}

// PolicyChain combines multiple policies with AND semantics.
// All policies must allow (or skip) for the operation to proceed.
type PolicyChain struct {
	policies []WritePolicy
}

// NewPolicyChain creates a chain of policies evaluated in order.
func NewPolicyChain(policies ...WritePolicy) *PolicyChain {
	return &PolicyChain{policies: policies}
}

// Evaluate checks all policies in the chain.
// Returns PolicyDeny if any policy denies.
// Returns PolicyAllow if all policies allow or skip.
func (c *PolicyChain) Evaluate(req WriteRequest) PolicyResult {
	for _, policy := range c.policies {
		result := policy.Evaluate(req)
		if result.Decision == PolicyDeny {
			return result
		}
		// PolicyAllow or PolicySkip - continue to next policy
	}
	return PolicyResult{Decision: PolicyAllow}
}

// PathPrefixPolicy restricts writes to specific path prefixes.
type PathPrefixPolicy struct {
	AllowedPrefixes []string
}

// Evaluate checks if the path starts with an allowed prefix.
// For move operations, both source and destination paths are checked.
func (p *PathPrefixPolicy) Evaluate(req WriteRequest) PolicyResult {
	if len(p.AllowedPrefixes) == 0 {
		return PolicyResult{Decision: PolicySkip}
	}

	// Check source path
	pathStr := req.Path.String()
	sourceAllowed := false
	for _, prefix := range p.AllowedPrefixes {
		if pathStr == prefix || hasPathPrefix(pathStr, prefix) {
			sourceAllowed = true
			break
		}
	}

	if !sourceAllowed {
		return PolicyResult{
			Decision: PolicyDeny,
			Reason:   "path outside allowed prefixes",
		}
	}

	// For move operations, also check destination
	if req.Op == OpMove && req.MoveTo != nil {
		destStr := req.MoveTo.String()
		destAllowed := false
		for _, prefix := range p.AllowedPrefixes {
			if destStr == prefix || hasPathPrefix(destStr, prefix) {
				destAllowed = true
				break
			}
		}
		if !destAllowed {
			return PolicyResult{
				Decision: PolicyDeny,
				Reason:   "destination path outside allowed prefixes",
			}
		}
	}

	return PolicyResult{Decision: PolicyAllow}
}

// ReadOnlyPathPolicy denies writes to specific paths or patterns.
type ReadOnlyPathPolicy struct {
	ReadOnlyPaths []string
}

// Evaluate checks if the path is read-only.
func (p *ReadOnlyPathPolicy) Evaluate(req WriteRequest) PolicyResult {
	pathStr := req.Path.String()
	for _, roPath := range p.ReadOnlyPaths {
		if pathStr == roPath || hasPathPrefix(pathStr, roPath) {
			return PolicyResult{
				Decision: PolicyDeny,
				Reason:   "path is read-only",
			}
		}
	}
	return PolicyResult{Decision: PolicySkip}
}

// hasPathPrefix checks if path starts with prefix as a complete path segment.
func hasPathPrefix(path, prefix string) bool {
	if len(path) <= len(prefix) {
		return false
	}
	if path[:len(prefix)] != prefix {
		return false
	}
	// Ensure it's a path boundary
	return path[len(prefix)] == '/'
}
