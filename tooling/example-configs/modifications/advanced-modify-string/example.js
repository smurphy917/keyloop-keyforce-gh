module.exports = class {
	constructor({ config, runtimeConfig, session }) {
		console.log('Construct modifier with:', config, runtimeConfig, session);

		this.config = config;
		this.runtimeConfig = runtimeConfig;
		this.session = session;
	}

	// Optional - delete if not required
	async start() {
		// Called after all modifiers have been initialised and before the initialisation loop
		console.log('Start modifier');
	}

	// Optional - delete if not required
	initaliseIteration({ data, fileInfo }) {
		// Called for each file matched - note data can be read but should not be modified
		console.log('Initialise interation with:', data, fileInfo);
	}

	// Optional - delete if not required
	async preModify() {
		// Called after the initialisation loop before the modify loop
		console.log('Pre modify');
	}

	modifyIteration({ data, fileInfo }) {
		// Called for each file matched - main modification logic goes here
		console.log('Modify iteration with:', data, fileInfo);

		// Must return the updated file contents (even if the data has not been modified)
		return data;
	}

	// Optional - delete if not required
	async finish() {
		// Called after the modify loop
		console.log('Finish modifier');
	}
};