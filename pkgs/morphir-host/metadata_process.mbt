///|
priv enum MetadataProcessState {
  Fresh
  Retained(@metadata_wire.Snapshot)
  Refused
  Disposed
}

///|
priv enum MetadataQuiescence {
  Confirmed
  Unconfirmed(String)
}

///|
/// Bind the explicit process authority without acquisition during planning.
/// Missing grants refuse only when metadata is actually requested. A qualified
/// session owns binary transport and cleanup; saved frames grant no authority.
#cfg(any(target="native", target="js"))
pub fn Host::register_process_metadata_provider(
  self : Host,
  engine : @engine.Engine,
  grants : @metadata_grants.Grants?,
  workspace_root : String,
  invocation_root : String,
  timeout~ : Int32 = 120000,
  cancel_file~ : String = "",
  observer~ : @observe.Observer = @observe.Observer::noop(),
  audit_sink~ : MetadataAuditSink = MetadataAuditSink::noop(),
) -> Unit raise {
  if timeout < 6001 || timeout > 600000 {
    raise @config.Invalid("metadata.restore_invalid_deadline")
  }
  self.register_requested_metadata_provider(engine, fn(scope) raise {
    let operation = @platform.observation_id()
    let project = @identity.sha256(
      @utf8.encode(
        Json::array(
          [
            workspace_root,
            scope.workspace_root,
            scope.project_root,
            scope.project_name,
          ].map(Json::string),
        ).stringify(),
      ),
    )
    let audit = MetadataAuditContext::{
      sink: audit_sink,
      operation,
      project,
      evidence: None,
    }
    metadata_observe(
      observer,
      operation,
      project,
      Resolve,
      "metadata.acquire",
      fn() raise {
        guard grants is Some(granted) else {
          raise @linked_metadata.Invalid(
            "metadata.restore_host_grants_required",
            scope.project_root,
            "Select an explicit --metadata-grants file",
          )
        }
        let selected = granted.select(scope, workspace_root, invocation_root)
        audit.evidence = Some({
          service: @metadata_wire.SERVICE_ID,
          service_sha256: selected.service_sha256,
          service_verified: false,
          release: selected.release,
          native_revision: None,
          profile: "local-library-mvp",
          profile_version: "0.1.0-draft.1",
          assurance: "portable",
          profile_verified: false,
        })
        metadata_process_session(
          self, scope, selected, operation, project, timeout, cancel_file, observer,
          audit,
        )
      },
      audit=Some(audit),
    )
  })
}

///|
fn metadata_process_session(
  host : Host,
  scope : @engine.ProjectMetadataScope,
  grant : @metadata_grants.GrantedService,
  operation : String,
  project : String,
  timeout : Int32,
  cancel_file : String,
  observer : @observe.Observer,
  audit : MetadataAuditContext,
) -> MetadataSession raise {
  if !@platform.file_chunks_supported() || !@platform.process_supported() {
    raise @config.Invalid("metadata.restore_runtime_unavailable")
  }
  let deadline = @platform.monotonic_seconds() + timeout.to_double() / 1000.0
  let directory = @platform.temporary()
  let mut state = MetadataProcessState::Fresh
  let mut quiescence = MetadataQuiescence::Confirmed
  let mut cleanup_deadline : Double? = Some(deadline)
  fn check() -> Unit raise {
    if state is Disposed {
      raise @config.Invalid("metadata.restore_disposed")
    }
    if (host.cancelled)() ||
      (cancel_file != "" && @platform.kind(cancel_file) != 0) {
      raise @protocol.Invalid("Cancelled")
    }
    if @platform.monotonic_seconds() >= deadline {
      raise @config.Invalid("metadata.restore_deadline")
    }
  }
  let (policy, lock) = {
    errdefer dispose_build_tree(directory)
    let policy = metadata_read_file(
      grant.policy,
      @metadata_wire.MAX_REQUEST_BYTES,
      check,
    )
    let lock = metadata_read_file(
      grant.lock,
      @metadata_wire.MAX_REQUEST_BYTES,
      check,
    )
    if policy.length() + lock.length() > @metadata_wire.MAX_REQUEST_BYTES {
      raise @config.Invalid("metadata.restore_request_limit")
    }
    (policy, lock)
  }
  let origins = match scope.request {
    SharedLocalRestore(r) =>
      [
        r.service.origin,
        r.policy.origin,
        r.lock.origin,
        r.registry.origin,
        r.state.origin,
      ]
    Disabled => []
  }
  let frozen_scope = @identity.sha256(
    @utf8.encode(
      Json::array(
        ([
          project,
          grant.node,
          grant.node_sha256,
          grant.helper,
          grant.helper_bundle_sha256,
          grant.service,
          grant.service_sha256,
          grant.policy,
          @identity.sha256(policy),
          grant.lock,
          @identity.sha256(lock),
          grant.registry,
          grant.state,
          grant.release,
          "portable",
          "local-library-mvp",
          "0.1.0-draft.1",
        ] +
        origins).map(Json::string),
      ).stringify(),
    ),
  )
  let expected : @metadata_wire.Expected = {
    invocation: operation,
    project_scope: frozen_scope,
    release: grant.release,
    policy_sha256: @identity.sha256(policy),
    lock_sha256: @identity.sha256(lock),
  }
  fn identity() -> Unit raise {
    if audit.evidence is Some(e) {
      audit.evidence = Some({ ..e, service_verified: false, })
    }
    check()
    if metadata_hash_file(grant.node, check) != grant.node_sha256 {
      raise @config.Invalid("metadata.restore_executable_changed: Node pin")
    }
    if metadata_bundle_hash(grant.helper, check) != grant.helper_bundle_sha256 {
      raise @config.Invalid(
        "metadata.restore_executable_changed: host helper bundle pin",
      )
    }
    if metadata_hash_file(grant.service, check) != grant.service_sha256 {
      raise @config.Invalid(
        "metadata.restore_executable_changed: selected service pin",
      )
    }
    if audit.evidence is Some(e) {
      audit.evidence = Some({ ..e, service_verified: true, })
    }
  }
  fn exchange(name : String, input : Bytes) -> Bytes raise {
    check()
    identity()
    let path = directory + "/" + name
    @platform.mkdir(path)
    @platform.write_bytes(path + "/request.ionb", input)
    let budget = ((deadline - @platform.monotonic_seconds()) * 1000.0).to_int()
    if budget < 6001 {
      raise @config.Invalid("metadata.restore_deadline")
    }
    @platform.write(
      path + "/control.json",
      (
        {
          "profile": "morphir-metadata-exchange-v1",
          "invocation": operation,
          "projectScope": frozen_scope,
          "service": grant.service,
          "serviceSha256": grant.service_sha256,
          "input": path + "/request.ionb",
          "inputSha256": @identity.sha256(input),
          "output": path + "/response.ionb",
          "receipt": path + "/receipt.json",
          "budgetMs": budget,
          "cancelFile": cancel_file,
        } : Json).stringify(),
    )
    quiescence = Unconfirmed(path)
    let result = @platform.process(
      grant.node,
      [grant.helper, path + "/control.json"],
      directory,
      "",
      budget,
    )
    let receipt = metadata_receipt(path, operation, frozen_scope) catch {
      _ =>
        raise @config.Invalid(
          "metadata.restore_cleanup_unconfirmed: scratch retained",
        )
    }
    if build_field(receipt, "quiescent") is True {
      quiescence = Confirmed
    }
    if build_field(result, "exitCode") != Json::number(0.0) {
      let code = build_text(receipt, "code")
      if code == "execution.cancelled" {
        raise @protocol.Invalid("Cancelled")
      }
      raise @config.Invalid(
        if code.has_prefix("metadata.restore_") || code.has_prefix("execution.") {
          code
        } else {
          "metadata.restore_transport_failed"
        },
      )
    }
    guard quiescence is Confirmed else {
      raise @config.Invalid("metadata.restore_cleanup_unconfirmed")
    }
    if build_text(result, "stdout").length() > 16384 ||
      build_field(receipt, "result") != Json::string("succeeded") ||
      @wire.parse(build_text(result, "stdout")) != receipt ||
      build_text(receipt, "serviceSha256") != grant.service_sha256 {
      raise @config.Invalid("metadata.restore_invalid_receipt")
    }
    identity()
    let bytes = @platform.read_bytes(path + "/response.ionb")
    if build_text(receipt, "responseSha256") != @identity.sha256(bytes) ||
      build_field(receipt, "responseBytes") !=
      Json::number(bytes.length().to_double()) {
      raise @config.Invalid("metadata.restore_response_changed")
    }
    check()
    bytes
  }
  fn snapshot() -> @metadata_wire.Snapshot raise {
    match state {
      Retained(snapshot) => return snapshot
      Fresh => ()
      Refused => raise @config.Invalid("metadata.restore_session_refused")
      Disposed => raise @config.Invalid("metadata.restore_disposed")
    }
    errdefer {
      state = Refused
    }
    metadata_observe(
      observer,
      operation,
      project,
      ProfileCheck,
      "metadata.probe",
      fn() raise {
        let probe = exchange(
          "probe",
          @metadata_wire.capabilities_request(operation, frozen_scope),
        )
        @metadata_wire.admit_capabilities(probe, operation, frozen_scope)
        if audit.evidence is Some(e) {
          audit.evidence = Some({ ..e, profile_verified: true, })
        }
      },
      audit=Some(audit),
    )
    let response = metadata_observe(
      observer,
      operation,
      project,
      Resolve,
      "metadata.restore",
      fn() raise {
        exchange(
          "restore",
          @metadata_wire.snapshot_request(
            expected,
            policy,
            lock,
            grant.registry,
            grant.state,
            directory + "/restored",
          ),
        )
      },
      audit=Some(audit),
    )
    let snapshot = metadata_observe(
      observer,
      operation,
      project,
      Decode,
      "metadata.decode",
      fn() raise {
        let accepted = @metadata_wire.Snapshot::decode(response, expected)
        check()
        if audit.evidence is Some(e) {
          audit.evidence = Some({
            ..e,
            native_revision: Some(accepted.native_revision()),
          })
        }
        accepted
      },
      audit=Some(audit),
    )
    state = Retained(snapshot)
    snapshot
  }
  {
    capabilities: {
      restore_library: Some(fn(predicate) raise {
        if !@linked_metadata.is_target_names_predicate(predicate) {
          raise @linked_metadata.Invalid(
            "metadata.provider_unavailable", predicate, "The grant is for the target-name provider",
          )
        }
        metadata_process_boundary(scope.project_root, fn() raise {
          check()
          let restored = snapshot().restored()
          check()
          restored
        })
      }),
      load_context: Some(fn(resource, base) raise {
        metadata_process_boundary(resource, fn() raise {
          check()
          metadata_observe(
            observer,
            operation,
            project,
            Resolve,
            "metadata.context",
            fn() raise {
              let context = snapshot().context(resource, base)
              check()
              context
            },
            audit=Some(audit),
          )
        })
      }),
      target_names_interpreter: true,
      provider_observer: audit.provider_observer(),
    },
    dispose: fn() raise {
      if state is Disposed {
        return
      }
      metadata_observe(
        observer,
        operation,
        project,
        Cleanup,
        "metadata.dispose",
        fn() raise {
          if quiescence is Unconfirmed(path) {
            let receipt = metadata_receipt(path, operation, frozen_scope) catch {
              _ =>
                raise @config.Invalid(
                  "metadata.restore_cleanup_unconfirmed: scratch retained",
                )
            }
            if build_field(receipt, "quiescent") is True {
              quiescence = Confirmed
            }
          }
          guard quiescence is Confirmed else {
            raise @config.Invalid(
              "metadata.restore_cleanup_unconfirmed: scratch retained",
            )
          }
          let until = cleanup_deadline.unwrap_or(
            @platform.monotonic_seconds() + 5.0,
          )
          cleanup_deadline = None
          metadata_dispose_tree(directory, until)
          state = Disposed
        },
        audit=Some(audit),
      )
    },
  }
}
