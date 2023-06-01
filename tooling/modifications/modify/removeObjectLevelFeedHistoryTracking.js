module.exports = ({ data, fileInfo : { apiName }, config : { objects = [] } = {} }) => {
	if (objects.length > 0 && !objects.includes(apiName)) {
		return;
	}

	delete data.enableFeeds;
	delete data.recordTypeTrackFeedHistory;

	// Covers MD API format (if in source format will have no effect)
	if (data.fields) {
		data.fields.forEach(field => {
			delete field.trackFeedHistory;
		});
	}

	if (data.nameField) {
		delete data.nameField[0].trackFeedHistory;
	}
}