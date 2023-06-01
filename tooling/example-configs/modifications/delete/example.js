// Called for each matched file
module.exports = ({ file, fileInfo, config, runtimeConfig }) => {

	console.log('Delete iteration with:', file, fileInfo, config, runtimeConfig);

	// Return true to delete the file or false to keep it
	return /^Delete_Me/.test(fileInfo.apiName);
};