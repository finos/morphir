//! Shared real native provider construction for ordinary and observed startup.
use super::*;
use cap_std::fs::Dir;
use model_originals::observation::HostSourceObservationScope;
use morphir_devkit::ConfigLoadOptions;
use std::path::Path;

pub(in crate::commands::ui) struct PreparedNativeUi {
    workspace: Arc<NativeWorkspaceProvider>,
    playground: Arc<NativePlaygroundProvider>,
}
impl PreparedNativeUi {
    pub(in crate::commands::ui) fn workspace_provider(&self) -> Arc<NativeWorkspaceProvider> {
        self.workspace.clone()
    }
    pub(in crate::commands::ui) fn capabilities(&self) -> SessionCapabilities {
        SessionCapabilities {
            workspace: Some(self.workspace.clone()),
            playground: Some(self.playground.clone()),
            ..Default::default()
        }
    }
    pub(in crate::commands::ui) fn originals_provider(
        &self,
    ) -> provider::originals::OriginalsProvider {
        provider::originals::OriginalsProvider::Native(self.workspace.clone())
    }
}
pub(super) enum NativeStartupSource<'a> {
    Historical,
    Observed {
        held: Dir,
        scope: &'a HostSourceObservationScope,
    },
}
pub(super) fn prepare_native_ui(
    root: &Path,
    session: &str,
    home: crate::home::MorphirHome,
    options: ConfigLoadOptions,
    out: crate::commands::out_context::OutOverrides,
    originals: ModelOriginalsMode,
    source: NativeStartupSource<'_>,
) -> Result<PreparedNativeUi, crate::error::CliError> {
    let (provider, playground) = match source {
        NativeStartupSource::Historical => {
            let provider = NativeWorkspaceProvider::discover_with_options(root, session, options)?;
            (provider, None)
        }
        NativeStartupSource::Observed { held, scope } => {
            let provider =
                NativeWorkspaceProvider::discover_observed(held, root, session, options, scope)?;
            (provider, Some(scope))
        }
    };
    let provider = provider.with_out_overrides(out);
    let provider = match originals {
        ModelOriginalsMode::Disabled => provider,
        ModelOriginalsMode::Preview => {
            provider.authorize_originals_lookup(cap_std::ambient_authority())?
        }
    };
    // The playground intentionally uses fresh DEFAULT config options, as it
    // always did. Only the actual read owner is shared, never the policy.
    let playground = match playground {
        Some(scope) => NativePlaygroundProvider::in_workspace_observed(home, root, scope),
        None => NativePlaygroundProvider::in_workspace(home, root),
    };
    Ok(PreparedNativeUi {
        workspace: Arc::new(provider),
        playground: Arc::new(playground),
    })
}
pub(in crate::commands::ui) fn prepare_native_ui_observed(
    held: Dir,
    root: &Path,
    session: &str,
    home: crate::home::MorphirHome,
    options: ConfigLoadOptions,
    out: crate::commands::out_context::OutOverrides,
    scope: &HostSourceObservationScope,
) -> Result<PreparedNativeUi, crate::error::CliError> {
    prepare_native_ui(
        root,
        session,
        home,
        options,
        out,
        ModelOriginalsMode::Preview,
        NativeStartupSource::Observed { held, scope },
    )
}
