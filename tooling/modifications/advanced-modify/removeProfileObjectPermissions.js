const ModifyProfile = require('./base-classes/modifyProfile');

module.exports = class extends ModifyProfile {
	modifyIteration({ data, fileInfo : { apiName } }) {
		if (!this.allowModifyProfile(apiName)) {
			return;
		}

		delete data.objectPermissions;
	}
};