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
#external
type PendingConnectedInspection

///|
enum ConnectedInspectionPresentation {
  ProjectionInspected
  OriginalsOnly(String)
} derive(Eq)

///|
enum OriginalsPanel {
  NoOriginalOpening
  OriginalOpening(@document.OpenAttempt, ConnectedOpening)
  InspectingOriginals(
    @document.OpenAttempt,
    ConnectedOpening,
    PendingConnectedInspection,
    @document.OriginalInventory
  )
  OriginalsReady(ConnectedInspectionPresentation)
} derive(Eq)

///|
enum OriginalsPhase {
  Discovering
  SourceChoices
  OpeningSource
  ProjectChoices
  ReceivingFiles
  QueuedFiles
  InspectingFiles
  OpeningFailed
  OpeningRetired
} derive(Eq)

///|
impl Eq for ConnectedOpening with fn equal(self, other) {
  same_originals(self, other)
}

///|
impl Eq for PendingConnectedInspection with fn equal(self, other) {
  same_pending_inspection(self, other)
}

///|
extern "js" fn same_pending_inspection(
  a : PendingConnectedInspection,
  b : PendingConnectedInspection,
) -> Bool =
  #| (a,b) => a === b

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
  #| (receive, hash) => globalThis.morphirWorkbench.openConnectedModel(hash, receive)

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
    "inspection" => InspectingFiles
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
extern "js" fn originals_source_identity(
  opening : ConnectedOpening,
  index : Int32,
) -> FixedArray[String] =
  #| (opening,index) => opening.sourceIdentity(index)

///|
extern "js" fn originals_project_identity(
  opening : ConnectedOpening,
  index : Int32,
) -> FixedArray[String] =
  #| (opening,index) => opening.projectIdentity(index)

///|
fn originals_choice_attrs(
  opening : ConnectedOpening,
  index : Int32,
  source : Bool,
) -> @html.Attrs {
  if source {
    match originals_source_identity(opening, index) {
      [provider, locator] =>
        @html.Attrs::build()
        .data_set("model-source-provider", provider)
        .data_set("model-source-locator", locator)
      _ => @html.Attrs::build()
    }
  } else {
    match originals_project_identity(opening, index) {
      [project] => @html.Attrs::build().data_set("model-project-id", project)
      _ => @html.Attrs::build()
    }
  }
}

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
extern "js" fn originals_inspection_message(
  event : ConnectedOriginalsEvent,
) -> String =
  #| event => event.inspectionMessage || ''

///|
extern "js" fn originals_inspection_stage(
  event : ConnectedOriginalsEvent,
) -> PendingConnectedInspection =
  #| event => event.stage

///|
extern "js" fn take_inspection_originals(
  stage : PendingConnectedInspection,
  adopt : (OriginalsPayload) -> Unit,
) -> Bool =
  #| (stage,adopt) => stage.take(adopt) === 'taken'

///|
extern "js" fn hold_connected_inspection(
  stage : PendingConnectedInspection,
  enqueue : () -> Unit,
) =
  #| (stage,enqueue) => globalThis.morphirWorkbench.holdConnectedInspection(stage, enqueue)

///|
extern "js" fn inspect_connected_model(
  stage : PendingConnectedInspection,
  receive : (String) -> Unit,
) =
  #| (stage,receive) => { void globalThis.morphirWorkbench.inspectConnectedModel(stage, receive); }

///|
extern "js" fn settle_connected_inspection(stage : PendingConnectedInspection) =
  #| stage => stage.settle()

///|
extern "js" fn settle_connected_originals(owner : ConnectedOpening) =
  #| owner => owner.settleOriginals()

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
  match panel {
    OriginalOpening(_, owner) | InspectingOriginals(_, owner, _, _) =>
      dispose_originals(owner)
    NoOriginalOpening | OriginalsReady(_) => ()
  }
}

///|
fn dispose_originals_message(msg : Msg) -> Unit {
  match msg {
    OriginalsStarted(_, owner) => dispose_originals(owner)
    OriginalsChanged(_, event) =>
      dispose_originals(originals_event_owner(event))
    ConnectedInspected(_, owner, _, _) => dispose_originals(owner)
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
    OriginalOpening(current, actual)
    | InspectingOriginals(current, actual, _, _) =>
      current == attempt && same_originals(actual, owner)
    NoOriginalOpening | OriginalsReady(_) => false
  })
}

///|
fn original_opening_identity(
  panel : OriginalsPanel,
) -> (@document.OpenAttempt, ConnectedOpening)? {
  match panel {
    OriginalOpening(attempt, owner)
    | InspectingOriginals(attempt, owner, _, _) => Some((attempt, owner))
    NoOriginalOpening | OriginalsReady(_) => None
  }
}

///|
fn connected_payload_inventory(
  payload : OriginalsPayload,
) -> @document.OriginalInventory? {
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
    _ => return None
  }
  Some(
    @document.OriginalInventory::from_connected(
      files,
      originals_payload_directories(payload).iter().collect(),
      header,
    ),
  ) catch {
    _ => None
  }
}

///|
fn connected_originals_only(
  model : Model,
  attempt : @document.OpenAttempt,
  inventory : @document.OriginalInventory,
  reason : String,
) -> Model {
  if !model.document.is_current(attempt) {
    return model
  }
  let document = model.document.finish_originals(attempt, inventory) catch {
    _ =>
      return {
        ..model,
        document: model.document.reject(attempt),
        originals: NoOriginalOpening,
        busy: false,
        status: "The original files could not be retained",
      }
  }
  let disclosure = if document.document() is Some(_) {
    "The explorer still shows the previous model; these original files belong to the newly selected capture."
  } else {
    "No inspected model is available; the original files can be downloaded."
  }
  let message = reason + " " + disclosure
  {
    ..model,
    document,
    originals: OriginalsReady(OriginalsOnly(message)),
    originals_page: OriginalsPage::first(),
    busy: false,
    status: "Original files ready. " + message,
  }
}

///|
/// Pure adoption decision. The real worker reply and inventory are inputs;
/// only a returned application Cmd can settle the imperative opening owner.
fn finish_connected_model(
  model : Model,
  attempt : @document.OpenAttempt,
  inventory : @document.OriginalInventory,
  reply : Json,
) -> Model {
  if !model.document.is_current(attempt) {
    return model
  }
  if host_execution_blocks_replacement(model) {
    return {
      ..model,
      document: model.document.reject(attempt),
      originals: NoOriginalOpening,
      busy: false,
      status: "Resume or finish the retained host execution before replacing the model",
    }
  }
  if field(reply, "success") != Json::boolean(true) ||
    field(reply, "ir") == Json::null() {
    let reason = text(reply, "message")
    return connected_originals_only(
      model,
      attempt,
      inventory,
      if reason != "" && reason.length() <= 256 {
        reason
      } else {
        "Model inspection is unavailable."
      },
    )
  }
  let document = model.document.finish_connected(attempt, reply, inventory) catch {
    _ =>
      return connected_originals_only(
        model, attempt, inventory, "The inspected model could not be retained.",
      )
  }
  {
    ..model,
    document,
    originals: OriginalsReady(ProjectionInspected),
    originals_page: OriginalsPage::first(),
    busy: false,
    status: "Original files ready · captured model inspected",
    doc: Model,
    model_revision: model.model_revision + 1,
    history: replacement_history(model),
    query: "",
    selected: "",
    collapsed_modules: [],
    evaluation_result: Json::null(),
    evaluation_terminal: @outcomes.Absent,
    evaluation_host_execution: false,
    evaluation_entry: "",
    evaluation_arguments: "[]",
    host_draft: None,
    evaluation_revision: model.evaluation_revision + 1,
  }
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
        "inspection" | "received" => {
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
          if originals_event_kind(event) == "inspection" {
            let stage = originals_inspection_stage(event)
            let mut inventory = None
            let taken = take_inspection_originals(stage, payload => {
              inventory = connected_payload_inventory(payload)
            })
            guard taken && inventory is Some(inventory) else {
              return (
                {
                  ..model,
                  document: model.document.reject(attempt),
                  originals: NoOriginalOpening,
                  busy: false,
                  status: "The original files could not be retained",
                },
                @cmd.custom_cmd(_ => dispose_originals(owner)),
              )
            }
            // This is the genuine application Cmd, held BEFORE Scheduler.add.
            let inspect = @cmd.custom_cmd(scheduler => {
              inspect_connected_model(stage, reply => {
                scheduler.add(
                  emit(ConnectedInspected(attempt, owner, stage, reply)),
                )
              })
            })
            return (
              {
                ..model,
                originals: InspectingOriginals(attempt, owner, stage, inventory),
                status: "Original files verified · waiting to inspect the captured model",
              },
              @cmd.custom_cmd(scheduler => {
                hold_connected_inspection(stage, () => scheduler.add(inspect))
              }),
            )
          }
          let mut document = model.document
          let mut adopted = false
          let taken = take_originals(originals_event_stage(event), payload => {
            guard connected_payload_inventory(payload) is Some(inventory) else {
              return
            }
            try {
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
              originals: if taken &&
                adopted &&
                originals_inspection_message(event) != "" {
                OriginalsReady(
                  OriginalsOnly(
                    originals_inspection_message(event) +
                    (if model.document.document() is Some(_) {
                      " The explorer still shows the previous model; original files belong to the newly selected capture."
                    } else {
                      " No inspected model is available."
                    }),
                  ),
                )
              } else {
                NoOriginalOpening
              },
              originals_page: if taken && adopted {
                OriginalsPage::first()
              } else {
                model.originals_page
              },
              busy: false,
              status: if taken && adopted {
                "Original files ready" +
                (if originals_inspection_message(event) == "" {
                  ""
                } else {
                  " · " + originals_inspection_message(event)
                })
              } else {
                "The model opening expired or could not retain its original files"
              },
            },
            @cmd.custom_cmd(_ => {
              if taken && adopted {
                settle_connected_originals(owner)
              } else {
                dispose_originals(owner)
              }
            }),
          )
        }
        _ => {
          dispose_originals(owner)
          (model, @cmd.none)
        }
      }
    }
    ConnectedInspected(attempt, owner, stage, reply) => {
      guard owns_originals(model, attempt, owner) &&
        model.originals is InspectingOriginals(_, _, actual, inventory) &&
        same_pending_inspection(actual, stage) else {
        return (model, @cmd.custom_cmd(_ => dispose_originals(owner)))
      }
      let result = @json.parse(reply) catch { _ => Json::null() }
      let after = finish_connected_model(model, attempt, inventory, result)
      (
        after,
        @cmd.custom_cmd(_ => {
          if after.originals is OriginalsReady(_) {
            settle_connected_inspection(stage)
          } else {
            dispose_originals(owner)
          }
        }),
      )
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
    InspectingOriginals(_, _, _, _) =>
      @html.p("Inspecting the captured model…")
    OriginalsReady(ProjectionInspected) =>
      @html.p("Inspected model and original files from the selected capture")
    OriginalsReady(OriginalsOnly(message)) => @html.p(class="notice", message)
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
        attrs=@html.Attrs::build().data_set(
          "model-choice-phase",
          if source {
            "source"
          } else {
            "project"
          },
        ),
        [
          @html.span(if source { "Model sources" } else { "Projects" }),
          ..names.mapi((index, name) => {
            @html.button(
              class="secondary",
              attrs=originals_choice_attrs(owner, index, source),
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
      @html.div(
        class="original-files",
        attrs=@html.Attrs::build().data_set(
          "inventory-revision",
          revision.to_string(),
        ),
        [
          @html.h3("Original files"),
          @html.button(
            class="secondary",
            disabled=model.originals_archive != NoArchive,
            on_click=emit(DownloadInventoryArchive(revision)),
            "Download originals archive",
          ),
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
                  OriginalsPageChanged(
                    revision,
                    page.previous().unwrap_or(page),
                  ),
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
                  OriginalsPageChanged(
                    revision,
                    page.next(total).unwrap_or(page),
                  ),
                ),
                "Next",
              ),
            ],
          ),
        ],
      )
    }
    _ => @html.nothing
  }
}
