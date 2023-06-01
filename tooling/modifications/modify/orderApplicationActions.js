module.exports = ({ data, config : { sortOrder } }) => {

	const actionSorter = (a, b) => {
		const aSortKey = getSortKey(a, sortOrder);
		const bSortKey = getSortKey(b, sortOrder);

		if (aSortKey > bSortKey)  return  1;
		if (aSortKey == bSortKey) return  0;
		if (aSortKey < bSortKey)  return -1;
	};

	const getSortKey = (obj, properties) => {
		let sortKey = '';
		properties.forEach(property => {
			if (obj[property]) {
				sortKey += obj[property][0];
			}
		});
		return sortKey;
	};
		
	if (data.actionOverrides) {
		data.actionOverrides.sort(actionSorter);
	}

	if (data.profileActionOverrides) {
		data.profileActionOverrides.sort(actionSorter);
	}
};