// The workbench copy at /try/ links back to the site through this meta tag. The desktop host does not set it.
export function withSiteHome(html: string, href: string) {
  const end = html.indexOf('</head>');
  if (end < 0) throw new Error('workbench index.html has no </head>');
  return `${html.slice(0, end)}<meta name="morphir-site-home" content="${href}">${html.slice(end)}`;
}
