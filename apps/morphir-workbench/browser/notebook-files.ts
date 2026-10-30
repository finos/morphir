/** Browser-local file selection; notebook decoding stays in the shared MoonBit package. */
export function pickNotebook(receive: (reply: string) => void): void {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.ipynb,.dib';
  input.addEventListener('cancel', () => receive(JSON.stringify({cancelled: true})), {once: true});
  input.addEventListener('change', async () => {
    const file = input.files?.[0];
    if (!file) return receive(JSON.stringify({cancelled: true}));
    try {
      if (file.size > 8 * 1024 * 1024) throw new Error('Notebook exceeds the 8 MiB input limit.');
      const format = file.name.split('.').at(-1)?.toLowerCase();
      if (format !== 'ipynb' && format !== 'dib') throw new Error('Choose a Jupyter (.ipynb) or DIB (.dib) notebook.');
      const content = new TextDecoder('utf-8', {fatal: true}).decode(await file.arrayBuffer());
      receive(JSON.stringify({filename: file.name, format, content}));
    } catch (cause) {
      receive(JSON.stringify({error: cause instanceof Error ? cause.message : 'The notebook could not be read.'}));
    }
  }, {once: true});
  input.click();
}
