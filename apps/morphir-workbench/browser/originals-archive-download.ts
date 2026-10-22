/** Fixed effect only; no arbitrary raw-view callback, filename or URL escape. */
export function requestOriginalArchiveDownload(bytes: Uint8Array<ArrayBuffer>): void {
  const blob = new Blob([bytes], {type: 'application/zip'});
  const url = URL.createObjectURL(blob);
  // The timer privately retains this actual effect's backing/Blob/URL lifetime.
  let effect: {bytes: Uint8Array<ArrayBuffer>; blob: Blob; url: string} | undefined = {bytes, blob, url};
  function dispose(): void {const previous = effect; effect = undefined; if (previous) URL.revokeObjectURL(previous.url);}
  try {
    const link = document.createElement('a');
    link.href = url; link.download = 'morphir-originals.zip';
    document.body.append(link);
    try {link.click();}
    catch (error) {
      try {link.remove();} catch { /* Preserve the earlier click failure. */ }
      throw error;
    }
    link.remove();
    setTimeout(dispose, 1000);
  } catch (error) {try {dispose();} catch { /* Preserve the first browser effect failure. */ } throw error;}
}
