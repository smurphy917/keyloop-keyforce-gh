module.exports = ({ data, config : { userPermissions : userPermissionsToRemove = [] } = {} }) => {
	if (!data.userPermissions || userPermissionsToRemove.length === 0) {
		return;
	}

	data.userPermissions = data.userPermissions.filter(
		userPermission => !userPermissionsToRemove.includes(userPermission.name[0])
	);
}