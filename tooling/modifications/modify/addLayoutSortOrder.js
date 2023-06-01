module.exports = ({ data }) => {
	if (!data.platformActionList) {
		return;
	}

	const wrapper = data.platformActionList[0];

	if (!wrapper.platformActionListItems) {
		return;
	}
	
	let counter = 0;
	wrapper.platformActionListItems.forEach(item => item.sortOrder = [ counter++ ]);
}