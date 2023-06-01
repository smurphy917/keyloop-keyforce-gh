module.exports = ({ data }) => {
	if (!data.fieldPermissions) {
		return;
	}

	data.fieldPermissions = data.fieldPermissions.filter(
		fieldPermission => !(fieldPermission.editable[0] === 'false' && fieldPermission.readable[0] === 'false')
	);
}