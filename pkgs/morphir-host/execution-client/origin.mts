export function hostOrigin(value?: string | null) {
  if (!value) return null;
  const host = new URL(value);
  if (host.protocol !== 'http:' || host.hostname !== '127.0.0.1' || !host.port || host.pathname !== '/' || host.search || host.hash || host.username || host.password) {
    throw new Error('MORPHIR_WORKBENCH_HOST_URL must be http://127.0.0.1:<port> with no path, query or credentials.');
  }
  return host;
}
