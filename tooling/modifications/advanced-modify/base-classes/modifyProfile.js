module.exports = class RemoveFromProfile {
	constructor({ config }) {
		this.config = config;
		this.allProfiles = [];
	}

	initaliseIteration({ data, fileInfo : { apiName } }) {
		this.allProfiles.push({ name: apiName, isCustom: Boolean(data.custom && data.custom[0] === 'true') });
	}

	async preModify() {
		let profiles = this.allProfiles;

		if (this.config.profiles) {
			profiles = (this.config.listType === 'include') 
				? this.allProfiles.filter(profile => this.config.profiles.includes(profile.name))
				: this.allProfiles.filter(profile => !this.config.profiles.includes(profile.name));
		}

		if (Boolean(this.config.customOnly && this.config.customOnly.toLowerCase() === 'true')) {
			profiles = profiles.filter(profile => profile.isCustom);
		}
		
		this.profiles = profiles.map(profile => profile.name);
	}

	allowModifyProfile(apiName) {
		return this.profiles.includes(apiName);
	}
};