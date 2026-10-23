// Imperative UI boundary. Identity text locates DATA in the genuine DOM;
// OwnedOpening retains the nominal objects and decides actual acceptance.
export type ConnectedChoice = Readonly<{kind: 'source'; providerId: string; locator: string}>
  | Readonly<{kind: 'project'; projectId: string}>;
export type ChoiceDocument = Pick<Document, 'querySelectorAll'>;
export function clickConnectedChoice(root: ChoiceDocument, choice: ConnectedChoice, actualIndex: number, actualCount: number): 'clicked' | 'unavailable' {
  const buttons = root.querySelectorAll<HTMLButtonElement>(choice.kind === 'source'
    ? 'button[data-model-source-provider][data-model-source-locator]' : 'button[data-model-project-id]');
  // Refuse unexpected DOM rows before scanning attribute text. The count comes
  // from this opening's actual nominal list, never from a caller's quota. Native
  // selector/NodeList allocations remain separate browser-engine obligations.
  if (buttons.length !== actualCount) return 'unavailable';
  let selected: HTMLButtonElement | undefined;
  for (let index = 0; index < buttons.length; index++) {
    const candidate = buttons[index]!;
    const matches = choice.kind === 'source'
      ? candidate.getAttribute('data-model-source-provider') === choice.providerId && candidate.getAttribute('data-model-source-locator') === choice.locator
      : candidate.getAttribute('data-model-project-id') === choice.projectId;
    if (matches) {
      if (selected || index !== actualIndex) return 'unavailable';
      selected = candidate;
    }
  }
  const button = selected;
  if (!button?.isConnected || button.disabled) return 'unavailable';
  button.click();
  return 'clicked';
}
