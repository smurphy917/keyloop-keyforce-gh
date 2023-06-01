exports.build = (library, runtimeConfig) => {

    // runtimeConfig.environment    - All lowercase name of environment as known to Ant
    // runtimeConfig.instanceUrl    - Salesforce Instance URL to be used with Session Id for authentication
    // runtimeConfig.sessionId      - Salesforce Session Id to be used with Instance URL for authentication
    // runtimeConfig.dataDirectory  - Directory where data is stored

    return {

        source: {
            connectionType: "SalesforceSessionConnection",
            instanceUrl: runtimeConfig.instanceUrl,
            sessionId: runtimeConfig.sessionId,
            useBulkApi: true,
        },

        target: {
            connectionType: 'JsonFileConnection',             // This is the type of connection to use as the target
            targetDirectory: runtimeConfig.dataDirectory + '/pricing-data'
        },

        move: [

            {
                objectName: 'SBQQ__PriceRule__c'
            },
            {
                objectName: 'SBQQ__PriceCondition__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Rule__c',
                        lookupTarget: 'SBQQ__PriceRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__TestedVariable__c',
                        lookupTarget: 'SBQQ__SummaryVariable__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__FilterVariable__c',
                        lookupTarget: 'SBQQ__SummaryVariable__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__PriceAction__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Rule__c',
                        lookupTarget: 'SBQQ__PriceRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__SourceVariable__c',
                        lookupTarget: 'SBQQ__SummaryVariable__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__LookupQuery__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__PriceRule2__c',
                        lookupTarget: 'SBQQ__PriceRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ],
                recordFilters: [library.recordFilters.ifFieldIsNull('SBQQ__PriceRule2__c')]
            },
            {
                objectName: 'SBQQ__CustomScript__c'
            }
        ]
    }
};