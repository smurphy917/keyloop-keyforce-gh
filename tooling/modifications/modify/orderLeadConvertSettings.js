module.exports = ({ data }) => {

	const mappingFieldsSorter = (a, b) => {
		if (a.inputField[0] > b.inputField[0] ) {
			return 1;
		}
		if (a.inputField[0] < b.inputField[0]) {
			return -1;
		}
		return 0;
	};
	
	if (data && Array.isArray(data.objectMapping)) {
		data.objectMapping.forEach(objectMapping => {
			if (Array.isArray(objectMapping.mappingFields)) {
				objectMapping.mappingFields.sort(mappingFieldsSorter);
			}
		});
	}
};