/**
 * Docusaurus plugin to handle routes for the IR Checker.
 * Registers concrete paths /ir-checker/v1, /ir-checker/v2, etc. so SSG
 * generates valid output (a single dynamic /ir-checker/:version would
 * create an invalid path like "ir-checker/:version" on Windows).
 */
const SCHEMA_VERSIONS = ['v1', 'v2', 'v3', 'v4'];

module.exports = function (context, options) {
    return {
        name: 'morphir-dynamic-routes',
        async contentLoaded({ actions }) {
            const { addRoute } = actions;
            for (const version of SCHEMA_VERSIONS) {
                addRoute({
                    path: `/ir-checker/${version}`,
                    component: '@site/src/pages/ir-checker.tsx',
                    exact: true,
                });
            }
        },
    };
};
