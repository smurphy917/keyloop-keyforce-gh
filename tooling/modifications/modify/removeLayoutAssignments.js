module.exports = ({ data, config: { layouts : layoutAssignmentsToRemove = [] } = {} }) => {
	if (!data.layoutAssignments || layoutAssignmentsToRemove.length === 0) {
		return;
	}

	data.layoutAssignments = data.layoutAssignments.filter(
		layoutAssignment => !layoutAssignmentsToRemove.includes(layoutAssignment.layout[0])
	);
}