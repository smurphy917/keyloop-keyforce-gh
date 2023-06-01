module.exports = ({ data, fileInfo : { dirs }, config : { objects = [] } = {} }) => {
	const objectApiName = dirs[dirs.length - 2];

	if (objects.length > 0 && !objects.includes(objectApiName)) {
		return;
	}

	delete data.trackHistory;
}