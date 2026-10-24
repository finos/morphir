///|
async fn DesktopPresentation::report(
  self : DesktopPresentation,
  event : DesktopEvent,
) -> Unit noraise {
  if self.enabled {
    self.sequence += 1
    let text = desktop_event(self.sequence, event)
    try {
      if self.wire {
        @stdio.stderr.write(text)
      } else {
        @stdio.stdout.write(text)
      }
    } catch {
      _ => ()
    }
  }
}

///|
extern "c" fn presentation_exit(code : Int32) = "exit"
