//! Real selected corpus preparation, not an actual BrowserRun.
use super::*;
use crate::workbench::{
    BrowserPreparationErrorKind, BrowserSourceTerminal, Corpus, corpus::CorpusStorage,
    with_prepared_browser_clients,
};
fn corpus() -> Corpus {
    Corpus {
        storage: CorpusStorage::ModelOriginals(source(CORPUS)),
    }
}

#[test]
fn browser_public_01_same_full_selected_source_input_views_and_callback_value() {
    let source = corpus();
    let outcome = with_prepared_browser_clients(&source, &configuration(), |clients, loans| {
        assert_eq!(clients.case_count(), source.case_count());
        let mut count = 0;
        clients.visit(loans, |client, loans| {
            let _actual_source_position = (client.case_index(), client.run_index());
            let actions = client.actions(loans)?;
            for action in actions {
                let _input_only = (action.position(), action.kind());
                count += 1;
            }
            Ok(())
        })?;
        Ok::<_, crate::workbench::BrowserInputError>(count)
    })
    .unwrap();
    let (value, terminal) = outcome.into_parts();
    assert!(value.unwrap() > 0);
    assert_eq!(terminal, BrowserSourceTerminal::Quiescent);
}

#[test]
fn browser_public_02_actual_callback_error_owner_is_retained_without_format_or_clone() {
    #[derive(Debug)]
    struct ActualError(Box<u64>);
    let actual = ActualError(Box::new(7));
    let pointer = std::ptr::from_ref(actual.0.as_ref());
    let outcome =
        with_prepared_browser_clients(&corpus(), &configuration(), |_, _| Err::<(), _>(actual))
            .unwrap();
    let (value, terminal) = outcome.into_parts();
    let error = value.unwrap_err();
    assert_eq!(std::ptr::from_ref(error.0.as_ref()), pointer);
    assert_eq!(terminal, BrowserSourceTerminal::Quiescent);
}

#[test]
fn browser_public_03_wrong_selection_refuses_before_callback() {
    let configuration = RunConfiguration::from_json(r#"{"kind":"historical"}"#).unwrap();
    let calls = Cell::new(0);
    let result = with_prepared_browser_clients(&corpus(), &configuration, |_, _| {
        calls.set(calls.get() + 1);
        Ok::<_, ()>(())
    });
    assert!(
        matches!(result, Err(ref error) if error.kind() == BrowserPreparationErrorKind::WrongConfiguration)
    );
    assert_eq!(calls.get(), 0);
}

#[test]
fn browser_public_04_other_prepared_source_loan_cannot_receive_this_client_view() {
    let mut exercised = false;
    let mut refused = false;
    with_prepared_browser_clients(&corpus(), &configuration(), |clients, loans| {
        clients.visit(loans, |client, _| {
            if !exercised {
                exercised = true;
                let result = with_prepared_browser_clients(
                    &corpus(),
                    &configuration(),
                    |_, foreign_loans| {
                        refused = client.actions(foreign_loans).is_err();
                        Ok::<_, ()>(())
                    },
                )
                .unwrap();
                assert!(result.into_parts().0.is_ok());
            }
            Ok::<_, crate::workbench::BrowserInputError>(())
        })?;
        Ok::<_, crate::workbench::BrowserInputError>(())
    })
    .unwrap();
    assert!(exercised);
    assert!(
        refused,
        "a genuine separate preparation must not lend its owners to this client"
    );
}
