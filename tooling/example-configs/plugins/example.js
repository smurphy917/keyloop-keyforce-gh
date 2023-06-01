module.exports = async ({ arguments, modules, session }) => {

	const fs          = require('fs');
	const { jsforce } = modules;

	console.log('-----------------------------------------------------------------------');
	console.log('Hello, I am an example JavaScript plugin being run through NodeJS.\n');

	console.log('These are the modules available to me:');
	console.log(Object.keys(modules));

	console.log();

	console.log('This is the configuration I have been given:\n');

	console.log('Arguments:');
	console.log(arguments);

	console.log();

	console.log('Session:');
	console.log(Object.keys(session));

	console.log();

	console.log('Here is a source directory listing based on the configuration provided:');
	console.log(fs.readdirSync(arguments.sourceDir));

	console.log();

	console.log('Here is some information from Salesforce:');

	const connection = new jsforce.Connection({
		serverUrl : session.instanceUrl,
		sessionId : session.sessionId,
		version   : session.apiVersion
	});

	const identity = await connection.identity();

	console.log('User ID         :', identity.user_id        );
	console.log('Organization ID :', identity.organization_id);
	console.log('Username        :', identity.username       );
	console.log('Display Name    :', identity.display_name   );
	console.log('-----------------------------------------------------------------------');
}