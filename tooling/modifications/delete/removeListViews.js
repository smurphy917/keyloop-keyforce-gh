module.exports = ({ fileInfo : { apiName, dirs }, config : { all = [], objects = {} } = {} }) => {

	for (const entry of all) {
		if (isMatch(entry, apiName)) {
			return true;
		}
	}

	for (const [ objectName, entries ] of Object.entries(objects)) {
		for (const entry of entries) {
			if (dirs[dirs.length - 2] === objectName && isMatch(entry, apiName)) {
				return true;
			}
		}
	}
	
	return false;
}

const isPositiveRegex  = str => str.substring(0, 1) === '/' && str.substring(str.length - 1) === '/';
const isNegativeRegex  = str => str.substring(0, 2) === '!/' && str.substring(str.length - 1) === '/';
const getPositiveRegex = str => new RegExp(str.substring(1, str.length -1));
const getNetativeRegex = str => new RegExp(str.substring(2, str.length -1));
const isMatch          = (entry, apiName) => entry === apiName || (isPositiveRegex(entry) && getPositiveRegex(entry).test(apiName)) || (isNegativeRegex(entry) && !getNetativeRegex(entry).test(apiName));