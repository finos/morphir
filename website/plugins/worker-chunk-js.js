/**
 * Docusaurus plugin to fix worker chunks so the browser can execute them.
 * Webpack emits worker chunks from .ts sources with a .ts extension; the dev server
 * then serves them as video/mp2t (MPEG-TS), so the browser refuses to execute them.
 *
 * - Patch MIME lookup at load time so .ts → application/javascript (fixes dev middleware).
 * - configureWebpack: try to force chunk filenames to .js (may not apply to worker chunks).
 * - beforeDevServer: patch responses so .ts requests get Content-Type: application/javascript.
 */

(function patchMimeForTs() {
  try {
    const mime = require('mime');
    const orig = mime.getType.bind(mime);
    if (orig) {
      mime.getType = function (path) {
        if (path && (path.endsWith('.ts') || path.endsWith('.tsx'))) {
          return 'application/javascript';
        }
        return orig(path);
      };
    }
  } catch (_) {}
  try {
    const mimeTypes = require('mime-types');
    const origLookup = mimeTypes.lookup.bind(mimeTypes);
    if (origLookup) {
      mimeTypes.lookup = function (path) {
        if (path && (path.endsWith('.ts') || path.endsWith('.tsx'))) {
          return 'application/javascript';
        }
        return origLookup(path);
      };
    }
  } catch (_) {}
})();

module.exports = function () {
  return {
    name: 'worker-chunk-js',
    configureWebpack(config, isServer) {
      if (isServer) return {};
      return {
        output: {
          chunkFilename: (pathData) => {
            const chunk = pathData.chunk;
            const name = chunk?.name ?? chunk?.id ?? 'chunk';
            const nameStr = typeof name === 'string' ? name.replace(/\.ts$/i, '') : String(name);
            const hash =
              (chunk?.contentHash && typeof chunk.contentHash === 'object' && chunk.contentHash.javascript) ||
              pathData.contentHash ||
              '';
            return hash ? `${nameStr}.${hash}.js` : `${nameStr}.js`;
          },
        },
      };
    },
    beforeDevServer(app) {
      app.use((req, res, next) => {
        if (req.url && /\.ts(?:\?|$)/.test(req.url)) {
          const jsType = 'application/javascript; charset=utf-8';
          const originalSetHeader = res.setHeader.bind(res);
          res.setHeader = function (name, ...args) {
            if (String(name).toLowerCase() === 'content-type') {
              const value = args[0];
              const str = Array.isArray(value) ? value[0] : value;
              if (typeof str === 'string' && str.includes('video/mp2t')) {
                return originalSetHeader('Content-Type', jsType);
              }
            }
            return originalSetHeader(name, ...args);
          };
          const originalWriteHead = res.writeHead.bind(res);
          res.writeHead = function (statusCode, statusMessageOrHeaders, headers) {
            let a2 = statusMessageOrHeaders;
            let a3 = headers;
            const h = typeof a2 === 'object' && a2 !== null ? a2 : a3;
            if (h && h['Content-Type'] && String(h['Content-Type']).includes('video/mp2t')) {
              const fixed = { ...h, 'Content-Type': jsType };
              if (typeof a2 === 'object' && a2 !== null) {
                a2 = fixed;
              } else {
                a3 = typeof a3 === 'object' && a3 !== null ? { ...a3, 'Content-Type': jsType } : { 'Content-Type': jsType };
              }
            }
            return a3 !== undefined ? originalWriteHead(statusCode, a2, a3) : originalWriteHead(statusCode, a2);
          };
        }
        next();
      });
    },
  };
};
