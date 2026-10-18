///|
test "legacy policy consumers share the canonical capability policy type" {
  let old : @execution.AdmissionPolicy = @execution.AdmissionPolicy::Permissive
  let current : @execution.CapabilityPolicy = old
  assert_true(current is Permissive)
  let strict : @execution.AdmissionPolicy = @execution.CapabilityPolicy::Strict
  assert_true(strict is Strict)
}
