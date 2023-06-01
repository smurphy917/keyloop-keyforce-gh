module.exports = ({ data }) => {
	if (Array.isArray(data.rules)) {
		data.rules.forEach(rule => {
			if (rule.formula) {
				rule.formula[0] = rule.formula[0].replace(/\r\n|\r|\n/g, ' ');
			}
		});
	}
};