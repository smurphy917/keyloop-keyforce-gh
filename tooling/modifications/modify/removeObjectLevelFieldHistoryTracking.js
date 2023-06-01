module.exports = ({ data, fileInfo : { apiName }, config : { objects = [] } ={} }) => {
	if (objects && objects.length > 0 && !objects.includes(apiName)) {
		return;
	}

	delete data.enableHistory;
	delete data.recordTypeTrackHistory;

	// Covers MD API format (if in source format will have no effect)
	if (data.fields) {
		data.fields.forEach(field => {
			delete field.trackHistory;
		});
	}

	if (data.nameField) {
		delete data.nameField[0].trackHistory;
	}
}