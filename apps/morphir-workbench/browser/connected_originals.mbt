///|
#external
type ConnectedOpening

///|
#external
type ConnectedOriginalsEvent

///|
#external
type OriginalsStage

///|
#external
type OriginalsPayload

///|
#external
type OriginalsHasher

///|
enum OriginalsPanel {
  NoOriginalOpening
  OriginalOpening(@document.OpenAttempt, ConnectedOpening)
} derive(Eq)

///|
enum OriginalsPhase {
  Discovering
  SourceChoices
  OpeningSource
  ProjectChoices
  ReceivingFiles
  QueuedFiles
  OpeningFailed
  OpeningRetired
} derive(Eq)

///|
impl Eq for ConnectedOpening with fn equal(self, other) {
  same_originals(self, other)
}

///|
extern "js" fn originals_hasher(
  update : (Bytes) -> Unit,
  hex : () -> String,
) -> OriginalsHasher =
  #| (update, hex) => ({ update, hex })

///|
fn make_originals_hasher() -> OriginalsHasher {
  let hash = @crypto.SHA256::new()
  originals_hasher(bytes => hash.update(bytes), () => {
    @crypto.bytes_to_hex_string(hash.finalize())
  })
}

///|
extern "js" fn open_originals(
  receive : (ConnectedOriginalsEvent) -> Unit,
  hash : () -> OriginalsHasher,
) -> ConnectedOpening =
  #| (receive, hash) => globalThis.morphirWorkbench.openOriginals(hash, receive)

///|
extern "js" fn dispose_originals(opening : ConnectedOpening) =
  #| opening => globalThis.morphirWorkbench.disposeOriginals(opening)

///|
extern "js" fn same_originals(
  a : ConnectedOpening,
  b : ConnectedOpening,
) -> Bool =
  #| (a,b) => a === b

///|
extern "js" fn originals_phase_name(opening : ConnectedOpening) -> String =
  #| opening => opening.view()

///|
fn originals_phase(opening : ConnectedOpening) -> OriginalsPhase {
  match originals_phase_name(opening) {
    "discovering" => Discovering
    "sources" => SourceChoices
    "opening" => OpeningSource
    "projects" => ProjectChoices
    "receiving" => ReceivingFiles
    "queued" => QueuedFiles
    "failed" => OpeningFailed
    _ => OpeningRetired
  }
}

///|
extern "js" fn originals_source_names(
  opening : ConnectedOpening,
) -> FixedArray[String] =
  #| opening => opening.sourceNames()

///|
extern "js" fn originals_project_names(
  opening : ConnectedOpening,
) -> FixedArray[String] =
  #| opening => opening.projectNames()

///|
extern "js" fn choose_originals_source(
  opening : ConnectedOpening,
  index : Int32,
) =
  #| (opening,index) => opening.chooseSource(index)

///|
extern "js" fn choose_originals_project(
  opening : ConnectedOpening,
  index : Int32,
) =
  #| (opening,index) => opening.chooseProject(index)

///|
extern "js" fn originals_event_kind(event : ConnectedOriginalsEvent) -> String =
  #| event => event.kind

///|
extern "js" fn originals_event_owner(
  event : ConnectedOriginalsEvent,
) -> ConnectedOpening =
  #| event => event.opening

///|
extern "js" fn originals_event_stage(
  event : ConnectedOriginalsEvent,
) -> OriginalsStage =
  #| event => event.stage

///|
extern "js" fn originals_event_error(event : ConnectedOriginalsEvent) -> String =
  #| event => event.message

///|
extern "js" fn take_originals(
  stage : OriginalsStage,
  adopt : (OriginalsPayload) -> Unit,
) -> Bool =
  #| (stage,adopt) => stage.take(adopt) === 'taken'

///|
extern "js" fn originals_payload_paths(
  payload : OriginalsPayload,
) -> FixedArray[String] =
  #| payload => payload.files.map(file => file.path)

///|
extern "js" fn originals_payload_bytes(
  payload : OriginalsPayload,
  index : Int32,
) -> Bytes =
  #| (payload,index) => payload.files[index].bytes

///|
extern "js" fn originals_payload_directories(
  payload : OriginalsPayload,
) -> FixedArray[String] =
  #| payload => payload.directories

///|
extern "js" fn originals_payload_header(
  payload : OriginalsPayload,
) -> FixedArray[UInt32] =
  #| payload => globalThis.morphirWorkbench.originalHeaderParts(payload)

///|
fn dispose_originals_panel(panel : OriginalsPanel) -> Unit {
  if panel is OriginalOpening(_, owner) {
    dispose_originals(owner)
  }
}

///|
fn dispose_originals_message(msg : Msg) -> Unit {
  match msg {
    OriginalsStarted(_, owner) => dispose_originals(owner)
    OriginalsChanged(_, event) =>
      dispose_originals(originals_event_owner(event))
    _ => ()
  }
}

///|
fn owns_originals(
  model : Model,
  attempt : @document.OpenAttempt,
  owner : ConnectedOpening,
) -> Bool {
  model.document.is_current(attempt) &&
  (match model.originals {
    OriginalOpening(current, actual) =>
      current == attempt && same_originals(actual, owner)
    NoOriginalOpening => false
  })
}

///|
fn update_originals(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    OpenOriginals => {
      if model.mode != ConnectedOriginals {
        return (model, @cmd.none)
      }
      if model.busy && !host_execution_blocks_replacement(model) {
        return ({ ..model, status: busy_reason, }, @cmd.none)
      }
      let (document, attempt) = match
        model.document.begin(host_retention(model)) {
        Started(document, attempt) => (document, attempt)
        Refused(_) =>
          return (
            {
              ..model,
              status: "Resume or finish the retained host execution before replacing the model",
            },
            @cmd.none,
          )
        Exhausted =>
          return (
            { ..model, status: "Reopen the page before opening another model", },
            @cmd.none,
          )
      }
      (
        {
          ..model,
          document,
          originals: NoOriginalOpening,
          busy: true,
          status: "Finding model sources…",
        },
        @cmd.custom_cmd(scheduler => {
          dispose_originals_panel(model.originals)
          let owner = open_originals(
            event => scheduler.add(emit(OriginalsChanged(attempt, event))),
            make_originals_hasher,
          )
          scheduler.add(emit(OriginalsStarted(attempt, owner)))
        }),
      )
    }
    OriginalsStarted(attempt, owner) => {
      if !model.document.is_current(attempt) {
        dispose_originals(owner)
        return (model, @cmd.none)
      }
      ({ ..model, originals: OriginalOpening(attempt, owner), }, @cmd.none)
    }
    ChooseOriginalSource(attempt, owner, index)
    | ChooseOriginalProject(attempt, owner, index) => {
      if !owns_originals(model, attempt, owner) {
        return (model, @cmd.none)
      }
      let source = msg is ChooseOriginalSource(_, _, _)
      let choices = if source && originals_phase(owner) == SourceChoices {
        originals_source_names(owner)
      } else if !source && originals_phase(owner) == ProjectChoices {
        originals_project_names(owner)
      } else {
        return (model, @cmd.none)
      }
      if index < 0 || index >= choices.length() {
        return (model, @cmd.none)
      }
      (
        {
          ..model,
          status: if source {
            "Finding projects…"
          } else {
            "Receiving original files…"
          },
        },
        @cmd.custom_cmd(_ => {
          if source {
            choose_originals_source(owner, index)
          } else {
            choose_originals_project(owner, index)
          }
        }),
      )
    }
    OriginalsChanged(attempt, event) => {
      let owner = originals_event_owner(event)
      if !owns_originals(model, attempt, owner) {
        dispose_originals(owner)
        return (model, @cmd.none)
      }
      match originals_event_kind(event) {
        "sources" => ({ ..model, status: "Choose a model source", }, @cmd.none)
        "projects" => ({ ..model, status: "Choose a project", }, @cmd.none)
        "failed" =>
          (
            {
              ..model,
              document: model.document.reject(attempt),
              originals: NoOriginalOpening,
              busy: false,
              status: originals_event_error(event),
            },
            @cmd.none,
          )
        "received" => {
          if host_execution_blocks_replacement(model) {
            dispose_originals(owner)
            return (
              {
                ..model,
                document: model.document.reject(attempt),
                originals: NoOriginalOpening,
                busy: false,
                status: "Resume or finish the retained host execution before replacing the model",
              },
              @cmd.none,
            )
          }
          let mut document = model.document
          let mut adopted = false
          let taken = take_originals(originals_event_stage(event), payload => {
            let paths = originals_payload_paths(payload)
            let files = Map([], capacity=paths.length())
            for index, path in paths {
              files[path] = originals_payload_bytes(payload, index)
            }
            let header = match originals_payload_header(payload) {
              [] => @document.OriginalSourceHeader::NotReported
              [major, minor, patch] =>
                @document.OriginalSourceHeader::Reported(
                  @document.OriginalRelease::new(major, minor, patch),
                )
              _ => return
            }
            try {
              let inventory = @document.OriginalInventory::from_connected(
                files,
                originals_payload_directories(payload).iter().collect(),
                header,
              )
              document = document.finish_originals(attempt, inventory)
              adopted = true
            } catch {
              _ => ()
            }
          })
          (
            {
              ..model,
              document: if taken && adopted {
                document
              } else {
                model.document.reject(attempt)
              },
              originals: NoOriginalOpening,
              originals_page: if taken && adopted {
                OriginalsPage::first()
              } else {
                model.originals_page
              },
              busy: false,
              status: if taken && adopted {
                "Original files ready"
              } else {
                "The model opening expired or could not retain its original files"
              },
            },
            @cmd.none,
          )
        }
        _ => {
          dispose_originals(owner)
          (model, @cmd.none)
        }
      }
    }
    OriginalsPageChanged(revision, page) => {
      guard model.document.original_inventory_for(revision) is Some(inventory) &&
        page.fits(inventory.entry_count()) else {
        return (model, @cmd.none)
      }
      ({ ..model, originals_page: page, }, @cmd.none)
    }
    DownloadInventoryFile(revision, path) => {
      guard model.document.original_inventory_for(revision) is Some(inventory) else {
        return (model, @cmd.none)
      }
      let artifact = inventory.download_file(path) catch {
        _ => return (model, @cmd.none)
      }
      let error = download_generated(Json::array([artifact]).stringify(), false)
      (
        {
          ..model,
          status: if error == "" {
            "Original file download started"
          } else {
            error
          },
        },
        @cmd.none,
      )
    }
    _ => (model, @cmd.none)
  }
}

///|
fn originals_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let chooser = match model.originals {
    NoOriginalOpening => @html.nothing
    OriginalOpening(attempt, owner) => {
      let source = match originals_phase(owner) {
        SourceChoices => true
        ProjectChoices => false
        _ => return originals_inventory_view(model, emit)
      }
      let names = if source {
        originals_source_names(owner)
      } else {
        originals_project_names(owner)
      }
      @html.div(
        class="evaluation-actions",
        [
          @html.span(if source { "Model sources" } else { "Projects" }),
          ..names.mapi((index, name) => {
            @html.button(
              class="secondary",
              on_click=emit(
                if source {
                  ChooseOriginalSource(attempt, owner, index)
                } else {
                  ChooseOriginalProject(attempt, owner, index)
                },
              ),
              name,
            )
          }),
          if names.is_empty() {
            @html.span("No available entries")
          } else {
            @html.nothing
          },
        ],
      )
    }
  }
  @html.div([chooser, originals_inventory_view(model, emit)])
}

///|
fn originals_inventory_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  match
    (model.document.inventory_revision(), model.document.original_inventory()) {
    (Some(revision), Some(inventory)) => {
      let total = inventory.entry_count()
      let page = if model.originals_page.fits(total) {
        model.originals_page
      } else {
        OriginalsPage::first()
      }
      let finish = (page.start() + originals_page_size).min(total)
      let entries : Array[@html.Html] = []
      for index = page.start(); index < finish; index = index + 1 {
        match inventory.entry(index) {
          Some(File(path)) =>
            entries.push(
              @html.li([
                @html.button(
                  class="ghost small",
                  on_click=emit(DownloadInventoryFile(revision, path)),
                  "Download " + path.to_string(),
                ),
              ]),
            )
          Some(Directory(path)) =>
            entries.push(@html.li(path.to_string() + "/"))
          None => ()
        }
      }
      @html.div(class="original-files", [
        @html.h3("Original files"),
        @html.p(
          match inventory.source_header {
            NotReported => "Original IR version not reported"
            Reported(release) => "Original IR " + release.to_release_string()
          },
        ),
        @html.ul(entries),
        @html.div(
          class="evaluation-actions",
          attrs=@html.Attrs::build()
            .role("group")
            .aria_label("Original files pagination"),
          [
            @html.button(
              class="ghost small",
              disabled=page.previous() is None,
              attrs=@html.Attrs::build().aria_label("Previous originals page"),
              on_click=emit(
                OriginalsPageChanged(revision, page.previous().unwrap_or(page)),
              ),
              "Previous",
            ),
            @html.span(
              "Entries " +
              (page.start() + 1).to_string() +
              " to " +
              finish.to_string() +
              " of " +
              total.to_string(),
            ),
            @html.button(
              class="ghost small",
              disabled=page.next(total) is None,
              attrs=@html.Attrs::build().aria_label("Next originals page"),
              on_click=emit(
                OriginalsPageChanged(revision, page.next(total).unwrap_or(page)),
              ),
              "Next",
            ),
          ],
        ),
      ])
    }
    _ => @html.nothing
  }
}
