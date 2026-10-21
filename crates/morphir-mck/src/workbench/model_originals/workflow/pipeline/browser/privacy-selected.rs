use super::*;
pub(super) fn check(input: BrowserClientInput<'_, '_, '_, '_, '_>) {
    let _ = (input.case_index(), input.run_index(), input.fixture());
}
pub(super) fn check_alias(alias: BrowserInputAlias<'_, '_>) {
    let _ = alias.kind();
}
