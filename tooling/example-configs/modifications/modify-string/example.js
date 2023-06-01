// Called for each matched file
module.exports = ({ data, fileInfo, config, runtimeConfig }) => {

	console.log('Modify iteration with:', data, fileInfo, config, runtimeConfig);

	// Modify the data as required
	data = data.replace(/cat/g, 'dog');

	// Must return the updated file contents (even if the data has not been modified)
	return data;
};