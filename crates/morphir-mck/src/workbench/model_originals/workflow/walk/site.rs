//! Private code-issued descriptor locations. No constructor accepts wire data.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Operand {
    Input,
    Expected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Site {
    operand: Operand,
    declaration: &'static str,
    variant: Option<&'static str>,
    field: &'static str,
}
impl Site {
    pub(super) const fn descriptor(
        operand: Operand,
        declaration: &'static str,
        variant: Option<&'static str>,
        field: &'static str,
    ) -> Self {
        Self {
            operand,
            declaration,
            variant,
            field,
        }
    }
    pub(crate) const fn parts(self) -> (Operand, &'static str, Option<&'static str>, &'static str) {
        (self.operand, self.declaration, self.variant, self.field)
    }
    #[cfg(test)]
    pub(crate) const fn test(
        operand: Operand,
        declaration: &'static str,
        variant: Option<&'static str>,
        field: &'static str,
    ) -> Self {
        Self::descriptor(operand, declaration, variant, field)
    }
}
