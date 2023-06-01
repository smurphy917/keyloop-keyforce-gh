module.exports = ({ fileInfo : { apiName }, config : { regex : pattern } = {} }) => {
	if (!pattern) {
		throw "Must set pattern for removeStandardApps modification";
	}

	return new RegExp(pattern).test(apiName);
}