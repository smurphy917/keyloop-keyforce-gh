module.exports = ({ data }) => {
	if (!data.platformActionList) {
		return;
	}

	const wrapper = data.platformActionList[0];

	if (!wrapper.platformActionListItems) {
		return;
	}
	
	wrapper.platformActionListItems = wrapper.platformActionListItems.sort(platformActionListSorter);
	wrapper.platformActionListItems.forEach(item => delete item.sortOrder);
}

const platformActionListSorter = (a, b) => {
	if (!a.sortOrder || !b.sortOrder) {
		return 0;
	}
	if (parseInt(a.sortOrder[0]) > parseInt(b.sortOrder[0])) {
		return 1;
	}
	if (parseInt(a.sortOrder[0]) == parseInt(b.sortOrder[0])) {
		return 0;
	}
	if (parseInt(a.sortOrder[0]) < parseInt(b.sortOrder[0])) {
		return -1;
	}
}