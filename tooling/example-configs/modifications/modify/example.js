// Called for each matched file
module.exports = ({ data, fileInfo, config, runtimeConfig }) => {

	console.log('Modify iteration with:', data, fileInfo, config, runtimeConfig);

	// Modify the data as required
	delete data.unwantedXmlNode;

	data.newXmlNode = 'Cheese';
};