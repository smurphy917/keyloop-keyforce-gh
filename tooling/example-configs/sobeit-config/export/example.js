exports.build = (library, runtimeConfig) => {

    // runtimeConfig.environment    - All lowercase name of environment as known to Ant
    // runtimeConfig.instanceUrl    - Salesforce Instance URL to be used with Session Id for authentication
    // runtimeConfig.sessionId      - Salesforce Session Id to be used with Instance URL for authentication
    // runtimeConfig.dataDirectory  - Directory where data is stored

    return {
        source: {
            connectionType     : "SalesforceSessionConnection",
            instanceUrl        : runtimeConfig.instanceUrl,
            sessionId          : runtimeConfig.sessionId,
            useBulkApi         : true,
        },

        target: {
            connectionType     : 'JsonFileConnection',
            targetDirectory    : runtimeConfig.dataDirectory + '/example',
        },

        move: [

            {
                objectName     : 'Account',
                includeFields  : ['Name', 'BillingStreet', 'BillingCountry'],
            }
        ]
    }
};