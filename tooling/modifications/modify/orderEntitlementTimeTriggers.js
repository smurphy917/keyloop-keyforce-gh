module.exports = ({ data }) => {

	const timeTriggerSorter = (a, b) => {
		const aSortKey = parseInt(a.timeLength[0]);
		const bSortKey = parseInt(b.timeLength[0]);

		if (aSortKey > bSortKey)  return  1;
		if (aSortKey == bSortKey) return  0;
		if (aSortKey < bSortKey)  return -1;
	};
		
	if (Array.isArray(data.milestones)) {
		data.milestones.forEach(milestone => {
			if (Array.isArray(milestone.timeTriggers)) {
				milestone.timeTriggers.sort(timeTriggerSorter);
			}
		})
	}
};