class MorphirInsightElement extends HTMLElement {

	static fqn = 'fqn';
	static arguments ='arguments';
	static observedAttributes = [MorphirInsightElement.fqn, MorphirInsightElement.arguments];
	static divId = 'divId'

	// Should be called to init the insight component
	init(distribution) {
		this.distribution = JSON.parse(distribution);

		this.app = Elm.Morphir.Web.Insight.init({
				node : this.shadowRoot.getElementById(MorphirInsightElement.divId),
				flags : {   distribution : this.distribution,
				config : {  fontSize : 12 , decimalDigit : 2 }
            }});

		this.app.ports.receiveFunctionName.send(this.fqn);
		this.app.ports.receiveFunctionArguments.send(this.arguments);
	}

	// Called automatically after connected to the DOM
	connectedCallback() {
		this.attachShadow({mode: 'open'});
		const insightDiv = document.createElement('div');
		insightDiv.id = MorphirInsightElement.divId;
   		this.shadowRoot.appendChild(insightDiv);

		this.fqn = this.getAttribute(MorphirInsightElement.fqn);
		this.arguments = JSON.parse(this.getAttribute(MorphirInsightElement.arguments));

	}

	// Called automatically after an observed attribute is read for the first time, or changed
	attributeChangedCallback(name, oldValue, newValue) {
		if (this.app && newValue && (oldValue !== newValue)) {
			switch (name) {
				case MorphirInsightElement.fqn:
					this.fqn = newValue;
					this.app.ports.receiveFunctionName.send(this.fqn);
					break;

				case MorphirInsightElement.arguments:
					this.arguments = JSON.parse(newValue);
					this.app.ports.receiveFunctionArguments.send(this.arguments);
					break;

				default:
					break;
		}
		}
	}

}

customElements.define('morphir-insight', MorphirInsightElement); 