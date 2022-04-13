/**
    The VisGraph class is defined to create a Custom Element which embeds the vis-graph library.
    This makes it possible to create graphs in Elm
**/

class VisGraph extends HTMLElement {
    constructor() {
        super();

    }

    drawGraph() {

        var graphObject = JSON.parse(this.getAttribute('graph'))

        var nodes = new vis.DataSet(
            graphObject.nodes,
        );

        var edges = new vis.DataSet(
            graphObject.edges
        );

        var data = {
            nodes: nodes,
            edges: edges
        };

        var options = {
            layout: {
                hierarchical: {
                    nodeSpacing: 100,
                    levelSeparation: 200,
                    direction: "DU",
                    sortMethod: "directed",
                    edgeMinimization: true
                },
            },
            edges: {
                smooth: true,
                arrows: "to",
            },
            autoResize: false,
            height: "1000px",
            width: "1000px",
            nodes: {
                physics: false

            },

        };

        var network = new vis.Network(this, data, options);

    }
    connectedCallback() { this.drawGraph() }
    attributeChangedCallback() { this.drawGraph() }
    disconnectedCallback() { }
    static get observedAttributes() { return ["graph"] }
}
window.customElements.define('vis-graph', VisGraph)

