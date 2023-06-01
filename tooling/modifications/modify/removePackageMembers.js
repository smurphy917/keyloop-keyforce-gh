module.exports = ({ data, config : { regex : membersPattern } = {} }) => {
	if (!data.types || !membersPattern) {
		return;
	}

	const regex = new RegExp(membersPattern)
	data.types.forEach(type => {
		if (type.members) {
			type.members = type.members.filter(member => !regex.test(member))
		}
	});
}